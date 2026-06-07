defmodule VnPartyWeb.GameChannel do
  use VnPartyWeb, :channel
  alias VnParty.Game
  alias VnParty.TruthResults
  alias VnParty.TruthDistortionUse
  alias VnParty.Game.Presence
  alias VnParty.Game.DistortionRules
  alias VnParty.Game.AnswerCommit
  alias VnParty.Telemetry
  alias VnParty.Repo
  alias VnPartyWeb.Endpoint
  alias Phoenix.PubSub

  @impl true
  def join("game:" <> room_code, %{"nickname" => nickname, "player_id" => player_id}, socket) do
    case Game.get_room_by_code_with_players(room_code) do
      nil ->
        {:error, %{reason: "Room not found"}}

      room ->
        socket =
          socket
          |> assign(:room_id, room.id)
          |> assign(:room_code, room.code)
          |> assign(:player_id, player_id)
          |> assign(:nickname, nickname)
          |> assign(:room_mode, Game.room_mode(room))

        case Game.get_player(player_id) do
          %VnParty.Game.Player{room_id: rid} when rid == room.id ->
            VnParty.PresenceScheduler.cancel(player_id)
            Presence.mark_connected(player_id)

            PubSub.subscribe(VnParty.PubSub, "room:#{room.id}:internal")
            send(self(), :after_join)

            game_state = get_game_state(room)
            response = build_join_response(room, game_state)
            {:ok, response, socket}

          _ ->
            {:error, %{reason: "Player not in this room. Join again from the home screen."}}
        end
    end
  end

  @impl true
  def join("game:" <> _room_code, _params, _socket) do
    {:error, %{reason: "Missing required parameters"}}
  end

  # ============================================================================
  # INCOMING MESSAGES - Players -> Server
  # ============================================================================

  @impl true
  def handle_in("start_game", payload, socket) do
    IO.puts("🚨 START_GAME RECEIVED room_id=#{inspect(socket.assigns[:room_id])} player_id=#{inspect(socket.assigns[:player_id])}")
    room_id = socket.assigns.room_id
    player_id = socket.assigns.player_id
    room = Game.get_room!(room_id)
    mode = Game.room_mode(room)

    Game.ensure_connected_host(room_id)
    player = Game.get_player!(player_id)

    unless player.is_host do
      {:reply, {:error, %{reason: "Only the host can start the game"}}, socket}
    else
      maybe_record_latency(socket, "start_game", payload, %{})
      # Drop disconnected lobby seats so counts and gameplay stay accurate.
      room_id
      |> Game.list_players()
      |> Enum.filter(fn p -> not p.connected end)
      |> Enum.each(fn p -> Game.remove_player_from_room(p.id) end)

      room = Game.get_room!(room_id)
      players = Game.list_players(room_id)
      connected_players = Game.round_active_players(room_id, max(room.current_round, 1))

      if mode == "truth_collapse" and length(connected_players) < 3 do
        {:reply, {:error, %{reason: "Truth Collapse requires at least 3 players"}}, socket}
      else
        if mode == "truth_collapse" do
          clear_truth_runtime_for_new_game(room_id, players)
          init_truth_stats(connected_players, true)
          init_truth_active_category(room_id)
        end

      case Game.start_game(room_id) do
      {:ok, room} ->
        # Broadcast to both players and display that game started
        game_started_payload = %{
          round: room.current_round,
          total_rounds: room.total_rounds,
          mode: mode,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        game_started_payload =
          if mode == "truth_collapse" do
            cat = get_truth_active_category(room.id)
            label = if cat, do: truth_category_label(cat), else: nil

            game_started_payload
            |> Map.put(:truth_theme, %{category: cat, category_label: label})
            |> Map.put(:distortion_limits, DistortionRules.limits_for_ui())
          else
            game_started_payload
          end

        broadcast_to_both(socket, "game_started", game_started_payload, "display:game_started", game_started_payload)

        if mode == "truth_collapse" do
          start_truth_round_flow(socket, room, room.current_round)
        else
          # Automatically request and broadcast first question immediately
          IO.puts("🎮 Game started, requesting question for round #{room.current_round}")
          question = generate_question_for_mode(room, room.current_round)
          IO.puts("📤 Broadcasting question: #{question.text}")

          # Broadcast question: full to display, options only to players
          display_question = question
          player_question = %{
            id: question.id,
            options: ["A", "B", "C", "D"],
            time_limit: question.time_limit
          }
          Game.record_commit_window(room_id, room.current_round, question.time_limit)
          broadcast_to_both(socket, "question_revealed", player_question, "display:question_revealed", display_question)

          # Set timer via PubSub so any connected channel can handle it (fixes stuck timer when host disconnects)
          timeout = (question.time_limit + 2) * 1000
          schedule_force_reveal(room_id, room.current_round, question.id, timeout)
        end

        {:reply, {:ok, %{state: room.state}}, socket}

      {:error, changeset} ->
        {:reply, {:error, %{errors: changeset}}, socket}
    end
      end
    end
  end

  @impl true
  def handle_in("request_question", %{"round" => round}, socket) do
    # In a real implementation, this would fetch from a question bank
    # For now, we'll send a mock question
    room = Game.get_room!(socket.assigns.room_id)
    question = generate_question_for_mode(room, round)

    # Broadcast question: full to display, options only to players
    display_question = question  # Full question with text
    # For players: only send option IDs (A, B, C, D) - no text, no question
    player_question = %{
      id: question.id,
      options: ["A", "B", "C", "D"],  # Just the option letters
      time_limit: question.time_limit
    }
    room_id = socket.assigns.room_id
    Game.record_commit_window(room_id, round, question.time_limit)
    broadcast_to_both(socket, "question_revealed", player_question, "display:question_revealed", display_question)

    # Set timer via PubSub so any connected channel can handle it
    timeout = (question.time_limit + 2) * 1000  # time_limit + 2 seconds buffer
    schedule_force_reveal(room_id, round, question.id, timeout)

    {:reply, {:ok, question}, socket}
  end

  @impl true
  def handle_in("commit_answer", payload, socket) do
    %{"answer" => answer, "question_id" => question_id} = payload
    room_id = socket.assigns.room_id
    player_id = socket.assigns.player_id

    maybe_record_latency(socket, "commit_answer", payload, %{question_id: question_id})

    # Generate salt and hash on server side for security
    salt = AnswerCommit.generate_salt()
    commit_hash = AnswerCommit.generate_commit_hash(answer, salt)

    # Get current round from room
    room = Game.get_room!(room_id)

    # Late commit defense: reject commits after window closes.
    if not Game.commit_window_open?(room_id, room.current_round) do
      {:reply, {:error, %{reason: "Commit window closed"}}, socket}
    else
      # Track timing manipulation (very late commits near deadline)
      delay_ms = Game.commit_delay_ms(room_id, room.current_round)
      late_threshold_ms = max((question_time_limit(room) - 2) * 1000, 0)
      violation = if is_integer(delay_ms) and delay_ms >= late_threshold_ms, do: "timing_manipulation", else: nil

      store_plaintext? = Application.get_env(:vn_party, :store_commit_plaintext, true)

      case Game.commit_answer_secure(room_id, player_id, room.current_round, question_id, commit_hash) do
      {:ok, commit} ->
        pending_key = {room_id, player_id, room.current_round}

        unless store_plaintext? do
          :ets.insert(:pending_answers, {pending_key, %{answer: answer, salt: salt}})
        end

        db_attrs = %{
          salt: salt,
          is_valid: true,
          commit_delay_ms: delay_ms,
          violation_reason: violation
        }

        db_attrs = if store_plaintext?, do: Map.put(db_attrs, :answer, answer), else: db_attrs

        save_committed_answer(commit, db_attrs, room_id, room.current_round)

        # Broadcast that this player has committed (but not the answer!)
        player_committed_payload = %{
          player_id: player_id,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }
        # Get player info for display
        players = Game.list_players(room_id)
        player = Enum.find(players, & &1.id == player_id)
        display_committed_payload = Map.put(player_committed_payload, :nickname, player.nickname)
        broadcast_to_both(socket, "player_committed", player_committed_payload, "display:player_committed", display_committed_payload)

        if Game.room_mode(room) == "truth_collapse" do
          commits_for_counts = Game.get_round_commits(room_id, room.current_round)
          counts = build_option_counts(commits_for_counts)
          Endpoint.broadcast("display:#{socket.assigns.room_code}", "display:option_counts_updated", %{round: room.current_round, counts: counts})
          broadcast!(socket, "option_counts_updated", %{round: room.current_round, counts: counts})
        end

        players = Game.list_players(room_id)
        connected_players = Game.round_active_players(room_id, room.current_round)
        commits = Game.get_round_commits(room_id, room.current_round)

        IO.puts("📊 Commits: #{length(commits)}/#{length(connected_players)} connected players")
        IO.puts("📋 Commit player IDs: #{inspect(Enum.map(commits, & &1.player_id))}")
        IO.puts("👥 Connected player IDs: #{inspect(Enum.map(connected_players, & &1.id))}")

        # Check if ALL connected players have committed (not just count, but actual player IDs)
        connected_player_ids = MapSet.new(Enum.map(connected_players, & &1.id))
        committed_player_ids = MapSet.new(Enum.map(commits, & &1.player_id))

        all_committed = MapSet.equal?(connected_player_ids, committed_player_ids) and MapSet.size(connected_player_ids) > 0

        if all_committed do
          schedule_auto_reveal_if_needed(room_id, room.current_round, question_id, socket)
        else
          IO.puts("⏳ Waiting for more players... #{MapSet.size(committed_player_ids)}/#{MapSet.size(connected_player_ids)}")
        end

        {:reply, {:ok, %{committed: true}}, socket}

      {:error, :replay_attack} ->
        {:reply, {:error, %{reason: "Replay attack detected"}}, socket}
      {:error, :late_commit} ->
        {:reply, {:error, %{reason: "Commit window closed"}}, socket}
      {:error, _changeset} ->
        {:reply, {:error, %{reason: "Failed to commit answer"}}, socket}
    end
    end
  end

  defp maybe_record_latency(socket, event, payload, meta) do
    client_ts = Map.get(payload, "client_timestamp_ms") || Map.get(payload, "client_timestamp")

    if is_integer(client_ts) do
      server_ts = System.system_time(:millisecond)
      latency = max(server_ts - client_ts, 0)

      room_id = socket.assigns[:room_id]
      player_id = socket.assigns[:player_id]

      mode = socket.assigns[:room_mode]

      round =
        case room_id do
          nil -> nil
          rid ->
            case :ets.lookup(:truth_room_phase, rid) do
              [{_, %{round: r}}] -> r
              _ -> nil
            end
        end

      attrs = %{
        room_id: room_id,
        player_id: player_id,
        event: event,
        direction: "c2s",
        mode: mode,
        round: round,
        client_timestamp_ms: client_ts,
        server_received_timestamp_ms: server_ts,
        latency_ms: latency,
        metadata: meta
      }

      if Game.cache_enabled?() do
        try do
          Telemetry.record_latency(attrs)
        rescue
          e ->
            require Logger
            Logger.warning("latency measurement insert failed: #{inspect(e)}")
        end
      else
        Task.start(fn ->
          try do
            Telemetry.record_latency(attrs)
          rescue
            e ->
              require Logger
              Logger.warning("latency measurement insert failed: #{inspect(e)}")
          end
        end)
      end
    end
  end

  @impl true
  def handle_in("heartbeat", _payload, socket) do
    Presence.mark_connected(socket.assigns.player_id)
    if room_id = socket.assigns[:room_id] do
      try do
        Game.get_room!(room_id)
      rescue
        _ -> :ok
      end
    end
    {:reply, {:ok, %{server_timestamp_ms: System.system_time(:millisecond)}}, socket}
  end

  @impl true
  def handle_in("leave_room", _payload, socket) do
    room_code = socket.assigns.room_code
    player_id = socket.assigns.player_id

    Game.player_left(player_id, room_code)

    {:stop, :normal, assign(socket, :left_voluntarily, true)}
  end

  @impl true
  def handle_in("close_room", _payload, socket) do
    Game.close_room_session(socket.assigns.room_id)
    {:stop, :normal, {:ok, %{closed: true}}, socket}
  end

  @impl true
  def handle_in("submit_prediction", payload, socket) do
    %{"option_id" => option_id} = payload
    mode = socket.assigns[:room_mode]

    if mode != "truth_collapse" do
      {:reply, {:error, %{reason: "Predictions are only available in Truth Collapse"}}, socket}
    else
      maybe_record_latency(socket, "submit_prediction", payload, %{option_id: option_id})

      current_round =
        case :ets.lookup(:truth_room_phase, socket.assigns.room_id) do
          [{_, %{round: r}}] -> r
          _ -> 1
        end

      key = {socket.assigns.room_id, current_round, socket.assigns.player_id}
      :ets.insert(:truth_predictions, {key, option_id})

      counts = build_prediction_counts(socket.assigns.room_id, current_round)
      counts_payload = %{round: current_round, counts: counts}
      Endpoint.broadcast("display:#{socket.assigns.room_code}", "display:option_counts_updated", counts_payload)
      broadcast!(socket, "option_counts_updated", counts_payload)

      {:reply, {:ok, %{saved: true}}, socket}
    end
  end

  @impl true
  def handle_in("use_distortion", %{"action" => action} = payload, socket) do
    maybe_record_latency(socket, "use_distortion", payload, %{action: action})

    case TruthDistortionUse.apply(
           socket.assigns.room_id,
           socket.assigns.player_id,
           socket.assigns.nickname,
           action,
           payload
         ) do
      {:ok, body} ->
        {:reply, {:ok, body}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("lock_fake_option", payload, socket) do
    room = Game.get_room!(socket.assigns.room_id)
    player_id = socket.assigns.player_id

    maybe_record_latency(socket, "lock_fake_option", payload, %{})

    cond do
      Game.room_mode(room) != "truth_collapse" ->
        {:reply, {:error, %{reason: "Distortions are only available in Truth Collapse"}}, socket}

      room.current_round >= room.total_rounds ->
        {:reply, {:error, %{reason: "No next round available"}}, socket}

      current_truth_phase(room.id) not in ["results", "discussion", "transition"] ->
        {:reply, {:error, %{reason: "Fake inject can only be used during the results phase"}}, socket}

      true ->
        phase = current_truth_phase(room.id)
        effect_round = distortion_effect_round(room, phase)
        lock_key = {room.id, effect_round, player_id}
        stats = get_truth_stats(player_id)
        cost = distortion_cost("inject_fake_option")

        cond do
          stats.charges < cost ->
            {:reply, {:error, %{reason: "Not enough distortion power"}}, socket}

          not DistortionRules.can_use?(room.id, player_id, "inject_fake_option") ->
            {:reply, {:error, %{reason: DistortionRules.denial_reason("inject_fake_option")}}, socket}

          :ets.lookup(:truth_fake_locks, lock_key) != [] ->
            {:reply, {:ok, %{locked: true, remaining_charges: stats.charges}}, socket}

          true ->
            update_truth_stats(player_id, fn s ->
              %{s | charges: max(0, s.charges - cost), di: s.di + cost * 10}
            end)

            :ets.insert(:truth_fake_locks, {lock_key, true})

            next_round = room.current_round + 1

            # Peek at the next question WITHOUT advancing history, so the actual
            # round start picks the same question the player sees in the preview.
            base_q = peek_next_truth_question(room, next_round)
            base_q = ensure_truth_question_option_capacity(base_q, count_connected(room.id) + 1)
            next_q = resize_truth_options_for_players(base_q, count_connected(room.id))

            # Cache so the actual round start reuses this exact question.
            :ets.insert(:truth_inject_preview, {{room.id, next_round}, base_q})

            preview =
              %{
                round: next_round,
                category: Map.get(next_q, :category),
                category_label: truth_category_label(Map.get(next_q, :category)),
                text: Map.get(next_q, :text),
                options: Enum.map(next_q.options, fn o -> %{id: o.id, text: o.text} end)
              }

            players_now = Game.list_players(room.id)
            stats_public =
              Enum.map(players_now, fn p ->
                s = get_truth_stats(p.id)
                %{player_id: p.id, tp: s.tp, di: s.di, ps: s.ps, charges: s.charges}
              end)
            broadcast!(socket, "truth_stats_updated", %{stats: stats_public})

            {:reply,
             {:ok,
              %{
                locked: true,
                remaining_charges: get_truth_stats(player_id).charges,
                preview_question: preview
              }}, socket}
        end
    end
  end

  @impl true
  def handle_in("set_fake_option_text", payload, socket) do
    %{"fake_text" => fake_text} = payload
    maybe_record_latency(socket, "set_fake_option_text", payload, %{})

    case TruthDistortionUse.complete_inject_fake(
           socket.assigns.room_id,
           socket.assigns.player_id,
           socket.assigns.nickname,
           fake_text
         ) do
      {:ok, body} ->
        {:reply, {:ok, body}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("truth_results_ready", payload, socket) do
    room = Game.get_room!(socket.assigns.room_id)

    if Game.room_mode(room) != "truth_collapse" do
      {:reply, {:error, %{reason: "Invalid mode"}}, socket}
    else
      maybe_record_latency(socket, "truth_results_ready", payload, %{})
      room_id = room.id
      round = room.current_round
      player_id = socket.assigns.player_id

      opts =
        case payload do
          %{"distortion" => %{"action" => _} = distortion} -> [distortion: distortion]
          _ -> []
        end

      case TruthResults.record_results_ready(room_id, player_id, round, opts) do
        {:ok, body} ->
          {:reply, {:ok, body}, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: reason}}, socket}
      end
    end
  end

  defp apply_distortion_for_player(socket, room, phase, action, dist_payload) do
    player_id = socket.assigns.player_id
    room_id = room.id

    cond do
      phase not in ["discussion", "results", "transition"] ->
        {:error, "Distortions can only be used during discussion or results"}

      action == "inject_fake_option" ->
        fake_text = Map.get(dist_payload, "fake_text", "")

        lock_key =
          {room.id, distortion_effect_round(room, phase), player_id}

        if :ets.lookup(:truth_fake_locks, lock_key) == [] do
          {:error, "You must lock the fake-option power first"}
        else
          case validate_distortion_payload("inject_fake_option", %{"fake_text" => fake_text}, room, player_id) do
            {:error, reason} -> {:error, reason}
            {:ok, cleaned} -> store_distortion_use(socket, room, phase, player_id, "inject_fake_option", cleaned, lock_key)
          end
        end

      true ->
        case validate_distortion_payload(action, dist_payload, room, player_id) do
          {:error, reason} -> {:error, reason}
          {:ok, cleaned} -> store_distortion_use(socket, room, phase, player_id, action, cleaned, nil)
        end
    end
  end

  defp store_distortion_use(socket, room, phase, player_id, action, cleaned_payload, lock_key) do
    cost = distortion_cost(action)
    stats = get_truth_stats(player_id)

    cond do
      stats.charges < cost ->
        {:error, "Not enough distortion power"}

      not DistortionRules.can_use?(room.id, player_id, action) ->
        {:error, DistortionRules.denial_reason(action)}

      true ->
        effect_round = distortion_effect_round(room, phase)

        DistortionRules.record_use!(room.id, player_id, action)
        update_truth_stats(player_id, fn s -> %{s | charges: max(0, s.charges - cost), di: s.di + cost * 10} end)
        :ets.insert(:truth_distortions, {room.id, effect_round, player_id, action, cleaned_payload})

        if lock_key do
          :ets.delete(:truth_fake_locks, lock_key)
        end

        Game.create_event(room.id, "distortion_used", %{
          action: action,
          round: effect_round,
          payload: cleaned_payload
        }, player_id)

        log_payload = %{
          round: effect_round,
          player_id: player_id,
          nickname: socket.assigns.nickname,
          action: action,
          payload: cleaned_payload,
          remaining_charges: get_truth_stats(player_id).charges
        }

        broadcast_to_both(socket, "distortion_used", log_payload, "display:distortion_used", log_payload)

        players_now = Game.list_players(room.id)

        stats_public =
          Enum.map(players_now, fn p ->
            s = get_truth_stats(p.id)
            %{player_id: p.id, tp: s.tp, di: s.di, ps: s.ps, charges: s.charges}
          end)

        broadcast!(socket, "truth_stats_updated", %{stats: stats_public})
        maybe_broadcast_discussion_refresh(socket, room, phase, effect_round)
        :ok
    end
  end

  defp maybe_broadcast_discussion_refresh(socket, room, phase, effect_round) do
    if phase in ["discussion", "transition"] and effect_round == room.current_round do
      broadcast_discussion_refresh(socket, room, effect_round)
    end

    :ok
  end

  defp broadcast_discussion_refresh(socket, room, round) do
    room_id = room.id
    {question, effects} = prepare_truth_round_question(room, round)
    set_truth_active_category(room_id, question.category)
    :ets.insert(:truth_round_data, {{room_id, round}, %{question: question, effects: effects}})

    timeline_labels = Enum.map(effects.category_timeline, &truth_category_label/1)
    discussion_seconds = 15

    phase_ends_at_ms =
      case :ets.lookup(:truth_discussion_mono, room_id) do
        [{^room_id, started_ms}] ->
          elapsed = System.monotonic_time(:millisecond) - started_ms
          remaining_ms = max(discussion_seconds * 1000 - elapsed, 0)
          System.system_time(:millisecond) + remaining_ms

        _ ->
          System.system_time(:millisecond) + discussion_seconds * 1000
      end

    player_payload = %{
      round: round,
      discussion_seconds: discussion_seconds,
      phase_ends_at_ms: phase_ends_at_ms,
      mode: "truth_collapse",
      question_id: question.id,
      category: question.category,
      category_label: truth_category_label(question.category),
      category_timeline: effects.category_timeline,
      category_timeline_labels: timeline_labels,
      options: Enum.map(question.options, & &1.id),
      distortion_refresh: true
    }

    display_payload =
      %{
        round: round,
        discussion_seconds: discussion_seconds,
        phase_ends_at_ms: phase_ends_at_ms,
        mode: "truth_collapse",
        question: nil,
        discussion_only: true,
        option_count: length(question.options),
        applied_distortions: effects.log,
        blind_targets: MapSet.to_list(effects.blind_targets),
        shuffle_targets: MapSet.to_list(effects.blind_targets),
        category: question.category,
        category_label: truth_category_label(question.category),
        category_timeline: effects.category_timeline,
        category_timeline_labels: timeline_labels,
        distortion_refresh: true
      }

    broadcast_to_both(socket, "discussion_started", player_payload, "display:discussion_started", display_payload)
  end

  @impl true
  def handle_in("truth_discussion_ready", payload, socket) do
    room = Game.get_room!(socket.assigns.room_id)

    if Game.room_mode(room) != "truth_collapse" do
      {:reply, {:error, %{reason: "Invalid mode"}}, socket}
    else
      maybe_record_latency(socket, "truth_discussion_ready", payload, %{})
      phase = current_truth_phase(room.id) || "discussion"

      distortion_note =
        case payload do
          %{"distortion" => %{"action" => action} = dist} when is_binary(action) ->
            case apply_distortion_for_player(socket, room, phase, action, dist) do
              :ok ->
                effect_round = distortion_effect_round(room, phase)
                maybe_broadcast_discussion_refresh(socket, room, phase, effect_round)
                "distortion_applied"

              {:error, reason} ->
                reason
            end

          _ ->
            nil
        end

      {:reply, {:ok, %{received: true, distortion_note: distortion_note}}, socket}
    end
  end

  @impl true
  def handle_in("reveal_answer", %{"commit_id" => commit_id}, socket) do
    # Get salt and answer from socket assigns
    salt = socket.assigns[:current_salt]
    answer = socket.assigns[:current_answer]

    if salt && answer do
      case Game.reveal_answer(commit_id, answer, salt) do
        {:ok, revealed_commit} ->
          # Broadcast revealed answer
          broadcast!(socket, "answer_revealed", %{
            player_id: socket.assigns.player_id,
            answer: answer,
            is_valid: revealed_commit.is_valid,
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          })

          {:reply, {:ok, %{is_valid: revealed_commit.is_valid}}, socket}

        {:error, _} ->
          {:reply, {:error, %{reason: "Invalid reveal"}}, socket}
      end
    else
      {:reply, {:error, %{reason: "No commit found"}}, socket}
    end
  end

  @impl true
  def handle_in("score_round", %{"correct_answer" => correct_answer, "round" => round}, socket) do
    room_id = socket.assigns.room_id

    # Get all commits for this round
    commits = Game.get_round_commits(room_id, round)

    # Score each commit
    scores = Enum.map(commits, fn commit ->
      # Hash tampering detection: reject if stored answer/salt doesn't match commit_hash.
      {:ok, commit} = Game.flag_hash_tampering_if_any(commit)

      is_correct = commit_text(commit) == correct_answer && commit.is_valid
      points = if is_correct, do: 100, else: 0

      # Update player score
      if is_correct do
        Game.update_player_score(commit.player_id, points)
      end

      %{
        player_id: commit.player_id,
        is_correct: is_correct,
        points: points
      }
    end)

    # Get updated player list with scores
    players = Game.list_players(room_id)

    # Broadcast scores
    broadcast!(socket, "round_scored", %{
      round: round,
      scores: scores,
      leaderboard: format_leaderboard(players)
    })

    {:reply, {:ok, %{scores: scores}}, socket}
  end

  @impl true
  def handle_in("next_round", _payload, socket) do
    room_id = socket.assigns.room_id
    _room = Game.get_room!(room_id)

    # Get current room to check round
    current_room = Game.get_room!(room_id)

    if current_room.current_round < current_room.total_rounds do
      case Game.advance_round(current_room) do
        {:ok, updated_room} ->
          round_started_payload = %{
            round: updated_room.current_round,
            total_rounds: updated_room.total_rounds
          }
          broadcast_to_both(socket, "round_started", round_started_payload, "display:round_started", round_started_payload)

          {:reply, {:ok, %{round: updated_room.current_round}}, socket}

        {:error, _} ->
          {:reply, {:error, %{reason: "Failed to advance round"}}, socket}
      end
    else
      # Game over
      Game.update_room_state(current_room, "game_end")

      players = Game.list_players(room_id)
      formatted_leaderboard = format_leaderboard(players)
      winner = List.first(formatted_leaderboard)

      # Broadcast game ended: full results to display, "look at screen" to players
      display_ended_payload = %{
        final_scores: formatted_leaderboard,
        winner: winner
      }
      player_ended_payload = %{
        message: "Game over! Look at the screen for final results!"
      }
      broadcast_to_both(socket, "game_ended", player_ended_payload, "display:game_ended", display_ended_payload)

      # Snapshot rematch electorate from the first results lobby view.
      connected_ids = players |> Enum.filter(& &1.connected) |> Enum.map(& &1.id)
      :ets.insert(:rematch_snapshot, {room_id, MapSet.new(connected_ids)})

      {:reply, {:ok, %{game_ended: true}}, socket}
    end
  end

  @impl true
  def handle_in("request_rematch", payload, socket) do
    room_id = socket.assigns.room_id
    player_id = socket.assigns.player_id
    maybe_record_latency(socket, "request_rematch", payload, %{})

    # Store rematch vote in ETS (shared across all processes)
    current_votes = case :ets.lookup(:rematch_votes, room_id) do
      [] -> MapSet.new()
      [{^room_id, votes}] -> votes
    end
    updated_votes = MapSet.put(current_votes, player_id)
    :ets.insert(:rematch_votes, {room_id, updated_votes})

    vote_payload = rematch_vote_payload(room_id)
    vote_count = vote_payload[:vote_count]
    total_players = vote_payload[:total_players]

    IO.puts("🔄 Rematch vote from player #{player_id}: #{vote_count}/#{total_players} (connected players only)")
    IO.puts("   All voters: #{inspect(vote_payload[:voters])}")
    IO.puts("   Snapshot total players: #{total_players}")

    broadcast_to_both(socket, "rematch_vote_updated", vote_payload, "display:rematch_vote_updated", vote_payload)

    # Trigger via internal PubSub so any alive channel can process it
    PubSub.broadcast(VnParty.PubSub, "room:#{room_id}:internal", {:check_rematch, room_id})

    {:reply, {:ok, %{vote_count: vote_count, total_players: total_players}}, socket}
  end

  @impl true
  def handle_in("decline_rematch", payload, socket) do
    room_id = socket.assigns.room_id
    player_id = socket.assigns.player_id
    maybe_record_latency(socket, "decline_rematch", payload, %{})

    # Mark this player as declined in ETS (shared across all processes)
    current_declined = case :ets.lookup(:rematch_declined, room_id) do
      [] -> MapSet.new()
      [{^room_id, declined}] -> declined
    end
    updated_declined = MapSet.put(current_declined, player_id)
    :ets.insert(:rematch_declined, {room_id, updated_declined})

    vote_payload = rematch_vote_payload(room_id)

    IO.puts("❌ Rematch declined: #{vote_payload[:declined_count]}/#{vote_payload[:total_players]}")

    broadcast_to_both(socket, "rematch_vote_updated", vote_payload, "display:rematch_vote_updated", vote_payload)

    PubSub.broadcast(VnParty.PubSub, "room:#{room_id}:internal", {:check_rematch, room_id})

    {:reply, {:ok, %{declined: true}}, socket}
  end

  @impl true
  def handle_in("ping", _payload, socket) do
    # Update last seen timestamp
    Game.update_player_connection(socket.assigns.player_id, true)
    {:reply, {:ok, %{timestamp: DateTime.utc_now() |> DateTime.to_iso8601()}}, socket}
  end

  @impl true
  def handle_in("get_state", payload, socket) do
    room = Game.get_room!(socket.assigns.room_id)
    maybe_record_latency(socket, "get_state", payload, %{})
    state = get_game_state(room)

    {:reply, {:ok, state}, socket}
  end

  # ============================================================================
  # CHANNEL LIFECYCLE
  # ============================================================================

  @impl true
  def handle_info(:after_join, socket) do
    room_id = socket.assigns.room_id
    players = Game.list_players(room_id)
    room = Game.get_room!(room_id)

    # Late joiners / reconnects get authoritative state on their channel.
    push(socket, "game_state", get_game_state(room))

    player_joined_payload = %{
      player_id: socket.assigns.player_id,
      nickname: socket.assigns.nickname,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      players: format_players(players, Game.room_mode(room))
    }
    broadcast_to_both(socket, "player_joined", player_joined_payload, "display:player_joined", player_joined_payload)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:send_question_to_new_joiner, question}, socket) do
    # Send question directly to this newly joined player (not broadcast)
    push(socket, "question_revealed", question)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:auto_request_question, round}, socket) do
    room_id = socket.assigns.room_id
    room = Game.get_room!(room_id)
    IO.puts("📝 Auto-requesting question for round #{round}")
    question = generate_question_for_mode(room, round)

    IO.puts("📤 Broadcasting question: #{question.text} (ID: #{question.id}, correct: #{question.correct})")

    # Broadcast question: full to display, options only to players
    display_question = question  # Full question with text
    # For players: only send option IDs (A, B, C, D) - no text, no question
    player_question = %{
      id: question.id,
      options: ["A", "B", "C", "D"],  # Just the option letters
      time_limit: question.time_limit
    }
    broadcast_to_both(socket, "question_revealed", player_question, "display:question_revealed", display_question)

    # Set timer via PubSub so any connected channel can handle it
    timeout = (question.time_limit + 2) * 1000  # time_limit + 2 seconds buffer
    schedule_force_reveal(room_id, round, question.id, timeout)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:truth_begin_answering, room_id, round}, socket) do
    # Deduplicate across all subscribed channel processes
    key = {:truth_q_started, room_id, round}
    if :ets.insert_new(:round_scored, {key, true}) do
      room = Game.get_room!(room_id)

      # Reuse the base question from the discussion phase (stored in truth_round_data)
      # instead of regenerating — regeneration would advance the question history and
      # potentially select a different question, causing discussion/answering mismatch.
      {question, effects} =
        case :ets.lookup(:truth_round_data, {room_id, round}) do
          [{{^room_id, ^round}, %{question: stored_q, effects: stored_eff}}] ->
            IO.puts("🔄 truth_begin_answering: reusing stored question #{stored_q.id} and effects for round #{round}")
            {stored_q, stored_eff}

          _ ->
            IO.puts("⚠️ truth_begin_answering: no stored question for round #{round}, generating fresh")
            prepare_truth_round_question(room, round)
        end

      # Distortions may swap the category (producing a new 9-option question) or inject
      # fake options. Always resize to the connected player count after applying distortions.
      conn = count_connected(room_id)
      question = ensure_truth_question_option_capacity(question, conn + 1)
      question = resize_truth_options_for_players(question, conn)

      IO.puts("🎯 truth_begin_answering: remove_targets=#{inspect(effects.remove_targets)}, blind_targets=#{inspect(effects.blind_targets)}")

      purge_distortions_for_round(room_id, round)
      :ets.insert(:truth_round_data, {{room_id, round}, %{question: question, effects: effects}})

      :ets.insert(:truth_room_phase, {room_id, %{round: round, phase: "answering"}})
      :ets.insert(:truth_answering_mono, {{room_id, round}, System.monotonic_time(:millisecond)})

      merged = merge_realities_used?(room_id, round)

      player_question = build_player_question_payload(room_id, question, effects)
      IO.puts("📤 truth_begin_answering: broadcasting question_revealed with personalized_options=#{inspect(Map.get(player_question, :personalized_options))}")

      display_payload =
        Map.merge(question, %{
          shuffle_targets: MapSet.to_list(effects.blind_targets),
          category_label: truth_category_label(Map.get(question, :category)),
          applied_distortions: effects.log,
          merged_realities_active: merged
        })

      Game.record_commit_window(room_id, round, question.time_limit)
      broadcast_to_both(socket, "question_revealed", player_question, "display:question_revealed", display_payload)

      timeout = (question.time_limit + 2) * 1000
      schedule_force_reveal(room_id, round, question.id, timeout)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:auto_reveal, round, question_id}, socket) do
    room_id = socket.assigns.room_id

    # Check if this round has already been scored (using ETS for shared state)
    scoring_key = {room_id, round}
    case :ets.lookup(:round_scored, scoring_key) do
      [{^scoring_key, _}] ->
        IO.puts("⚠️ Round #{round} already scored, skipping auto-reveal")
        {:noreply, socket}
      [] ->
        # Mark as scored atomically to prevent double scoring
        case :ets.insert_new(:round_scored, {scoring_key, true}) do
          true ->
            # We successfully marked it, proceed with scoring
            score_round_internal(room_id, round, question_id, socket)
          false ->
            # Another process already marked it, skip
            IO.puts("⚠️ Round #{round} already scored (race condition), skipping auto-reveal")
            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_info({:force_auto_reveal, room_id, round, question_id}, socket) do
    # Check if this round has already been scored (using ETS for shared state)
    scoring_key = {room_id, round}
    case :ets.lookup(:round_scored, scoring_key) do
      [{^scoring_key, _}] ->
        IO.puts("⚠️ Round #{round} already scored, skipping force auto-reveal")
        {:noreply, socket}
      [] ->
        # Mark as scored atomically to prevent double scoring
        case :ets.insert_new(:round_scored, {scoring_key, true}) do
          true ->
            # We successfully marked it, proceed with scoring
            score_round_force(room_id, round, question_id, socket)
          false ->
            # Another process already marked it, skip
            IO.puts("⚠️ Round #{round} already scored (race condition), skipping force auto-reveal")
            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_info({:auto_advance_round, %VnParty.Game.Room{} = room}, socket) do
    handle_info({:auto_advance_round, room.id, room.current_round}, socket)
  end

  @impl true
  def handle_info({:auto_advance_round, room_id, from_round}, socket) when is_integer(from_round) do
    dedupe_key = {:auto_advance_processed, room_id, from_round}

    if not :ets.insert_new(:round_scored, {dedupe_key, true}) do
      {:noreply, socket}
    else
    room = Game.get_room!(room_id)

    if room.current_round != from_round do
      {:noreply, socket}
    else
    if room.current_round < room.total_rounds do
      case Game.advance_round(room) do
        {:ok, updated_room} ->
          if Game.room_mode(updated_room) == "truth_collapse" do
            :ets.insert(:truth_room_phase, {updated_room.id, %{round: updated_room.current_round, phase: "transition"}})
          end

          round_started_payload = %{
            round: updated_room.current_round,
            total_rounds: updated_room.total_rounds,
            mode: Game.room_mode(updated_room),
            discussion_seconds: 15
          }

          if Game.room_mode(updated_room) == "truth_collapse" do
            start_truth_round_flow(socket, updated_room, updated_room.current_round)

            round_started_payload =
              case :ets.lookup(:truth_round_data, {updated_room.id, updated_room.current_round}) do
                [{{_, _}, %{question: q, effects: eff}}] when is_map(q) ->
                  cat = Map.get(q, :category)
                  opt_ids = Enum.map(q.options, & &1.id)
                  labels = Enum.map(eff.category_timeline || [cat], &truth_category_label/1)

                  Map.merge(round_started_payload, %{
                    category: cat,
                    category_label: truth_category_label(cat),
                    category_timeline_labels: labels,
                    option_ids: opt_ids
                  })

                _ ->
                  round_started_payload
              end

            broadcast_to_both(socket, "round_started", round_started_payload, "display:round_started", round_started_payload)
          else
            broadcast_to_both(socket, "round_started", round_started_payload, "display:round_started", round_started_payload)
            # Automatically request and broadcast question for next round immediately
            IO.puts("🔄 Round advanced, requesting question for round #{updated_room.current_round}")
            question = generate_question_for_mode(updated_room, updated_room.current_round)
            IO.puts("📤 Broadcasting question: #{question.text} (ID: #{question.id})")

            # Broadcast question: full to display, options only to players
            display_question = question
            player_question = %{
              id: question.id,
              options: ["A", "B", "C", "D"],
              time_limit: question.time_limit
            }
            broadcast_to_both(socket, "question_revealed", player_question, "display:question_revealed", display_question)

            # Set timer via PubSub so any connected channel can handle it
            timeout = (question.time_limit + 2) * 1000
            schedule_force_reveal(room_id, updated_room.current_round, question.id, timeout)
          end

        {:error, _} ->
          IO.puts("❌ Failed to advance round")
      end
    else
      # Game over
      Game.update_room_state(room, "game_end")

      players = Game.list_players(room_id)
      formatted_leaderboard =
        if Game.room_mode(room) == "truth_collapse" do
          format_truth_leaderboard(players)
        else
          format_leaderboard(players)
        end
      winner = List.first(formatted_leaderboard)

      # Broadcast game ended: full results to display, "look at screen" to players
      display_ended_payload = %{
        final_scores: formatted_leaderboard,
        winner: winner
      }
      player_ended_payload = %{
        message: "Game over! Look at the screen for final results!"
      }
      broadcast_to_both(socket, "game_ended", player_ended_payload, "display:game_ended", display_ended_payload)

      :ets.delete(:truth_room_phase, room_id)
      :ets.delete(:truth_discussion_mono, room_id)

      for r <- 1..10 do
        :ets.delete(:truth_answering_mono, {room_id, r})
      end

      schedule_internal_message(room_id, {:rematch_timeout, room_id}, 30_000)
    end

      {:noreply, socket}
    end
    end
  end

  @impl true
  def handle_info({:check_all_committed, room_id}, socket) do
    if socket.assigns[:room_id] == room_id do
      room = Game.get_room!(room_id)
      round = room.current_round

      if Game.room_mode(room) == "truth_collapse" and current_truth_phase(room_id) == "answering" do
        case :ets.lookup(:truth_round_data, {room_id, round}) do
          [{{^room_id, ^round}, %{question: q}}] ->
            schedule_auto_reveal_if_needed(room_id, round, q.id, socket)

          _ ->
            :ok
        end
      end
    end

    {:noreply, socket}
  end

  def handle_info({:check_rematch, room_id}, socket) do
    votes =
      case :ets.lookup(:rematch_votes, room_id) do
        [] -> MapSet.new()
        [{^room_id, v}] -> v
      end

    declined =
      case :ets.lookup(:rematch_declined, room_id) do
        [] -> MapSet.new()
        [{^room_id, d}] -> d
      end

    players = Game.list_players(room_id)
    snapshot_ids = rematch_snapshot_ids(room_id)
    total_players = MapSet.size(snapshot_ids)
    vote_count = MapSet.size(votes)
    declined_count = MapSet.size(declined)
    majority = div(total_players, 2) + 1

    decided_ids = MapSet.intersection(MapSet.union(votes, declined), snapshot_ids)
    all_decided = total_players > 0 and MapSet.equal?(decided_ids, snapshot_ids)
    majority_declined = declined_count >= majority

    IO.puts("🔄 Checking rematch: #{vote_count} votes, #{declined_count} declined, #{total_players} snapshot total")

    cond do
      total_players == 0 ->
        :ok

      majority_declined ->
        clear_rematch_state(room_id)

        cancelled_payload = %{message: "Majority declined rematch.", kick_to_home: true}
        broadcast_to_both(socket, "rematch_cancelled", cancelled_payload, "display:rematch_cancelled", cancelled_payload)

      all_decided and vote_count >= majority ->
        players_to_remove =
          Enum.filter(players, fn p ->
            MapSet.member?(snapshot_ids, p.id) and not MapSet.member?(votes, p.id)
          end)

        Enum.each(players_to_remove, fn p -> Game.remove_player_from_room(p.id) end)
        reset_room_for_rematch(room_id)
        clear_rematch_state(room_id)

        approved_payload = rematch_approved_payload(room_id, vote_count, votes)
        broadcast_to_both(socket, "rematch_approved", approved_payload, "display:rematch_approved", approved_payload)
        broadcast_room_reset_to_lobby(room_id)
        broadcast_game_state(room_id)

      all_decided ->
        clear_rematch_state(room_id)

        cancelled_payload = %{message: "Not enough yes votes for rematch.", kick_to_home: true}
        broadcast_to_both(socket, "rematch_cancelled", cancelled_payload, "display:rematch_cancelled", cancelled_payload)

      true ->
        IO.puts("⏳ Waiting for more decisions... (#{MapSet.size(decided_ids)}/#{MapSet.size(snapshot_ids)})")
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:rematch_timeout, room_id}, socket) do
    votes =
      case :ets.lookup(:rematch_votes, room_id) do
        [] -> MapSet.new()
        [{^room_id, v}] -> v
      end

    snapshot_ids = rematch_snapshot_ids(room_id)
    total_players = MapSet.size(snapshot_ids)
    majority = div(total_players, 2) + 1
    vote_count = MapSet.size(votes)
    players = Game.list_players(room_id)

    IO.puts("⏰ Rematch timeout reached. Final votes: #{vote_count}/#{total_players}")

    if total_players > 0 and vote_count >= majority do
      players_to_remove =
        Enum.filter(players, fn p ->
          MapSet.member?(snapshot_ids, p.id) and not MapSet.member?(votes, p.id)
        end)

      Enum.each(players_to_remove, fn p -> Game.remove_player_from_room(p.id) end)
      reset_room_for_rematch(room_id)
      clear_rematch_state(room_id)

      approved_payload = rematch_approved_payload(room_id, vote_count, votes)
      broadcast_to_both(socket, "rematch_approved", approved_payload, "display:rematch_approved", approved_payload)
      broadcast_room_reset_to_lobby(room_id)
      broadcast_game_state(room_id)
    else
      clear_rematch_state(room_id)

      cancelled_payload = %{message: "Rematch was not approved in time.", kick_to_home: true}
      broadcast_to_both(socket, "rematch_cancelled", cancelled_payload, "display:rematch_cancelled", cancelled_payload)
    end

    {:noreply, socket}
  end

  @impl true
  def terminate(reason, socket) do
    if socket.assigns[:room_id] do
      PubSub.unsubscribe(VnParty.PubSub, "room:#{socket.assigns.room_id}:internal")
    end

    if socket.assigns[:player_id] && socket.assigns[:room_code] do
      room_id = socket.assigns.room_id
      player_id = socket.assigns.player_id
      room_code = socket.assigns.room_code

      if should_remove_player_on_disconnect?(reason, socket) do
        room = Game.get_room!(room_id)

        if room.state not in ["lobby", "game_end"] do
          Game.mark_skip_next_round(room_id, player_id)
        end

        Game.player_left(player_id, room_code)
      else
        VnParty.PresenceScheduler.schedule_disconnect(player_id, room_id, room_code)
      end
    end

    maybe_register_rematch_disconnect_vote(socket)

    :ok
  end

  defp should_remove_player_on_disconnect?(reason, socket) do
    if socket.assigns[:left_voluntarily], do: false

    case reason do
      :normal -> false
      {:shutdown, :left} -> false
      {:shutdown, :nominate} -> false
      {:shutdown, _} -> false
      _ -> true
    end
  end

  defp build_join_response(room, game_state) do
    if room.state == "round_start" and room.current_round > 0 and
         Game.room_mode(room) != "truth_collapse" do
      question = generate_mock_question(room.current_round)

      player_question = %{
        id: question.id,
        options: ["A", "B", "C", "D"],
        time_limit: question.time_limit
      }

      Map.put(game_state, :current_question, player_question)
    else
      game_state
    end
  end

  # ============================================================================
  # HELPER FUNCTIONS
  # ============================================================================

  # Schedule force_auto_reveal via PubSub so any connected channel process can handle it.
  # This fixes the bug where the timer would not fire if the player who started the game disconnected.
  defp schedule_force_reveal(room_id, round, question_id, timeout_ms) do
    spawn(fn ->
      Process.sleep(timeout_ms)
      PubSub.broadcast(VnParty.PubSub, "room:#{room_id}:internal", {:force_auto_reveal, room_id, round, question_id})
    end)
  end

  defp schedule_internal_message(room_id, message, timeout_ms) do
    spawn(fn ->
      Process.sleep(timeout_ms)
      PubSub.broadcast(VnParty.PubSub, "room:#{room_id}:internal", message)
    end)
  end

  defp current_truth_phase(room_id) do
    case :ets.lookup(:truth_room_phase, room_id) do
      [{^room_id, %{phase: phase}}] when is_binary(phase) ->
        phase

      _ ->
        room = Game.get_room!(room_id)

        cond do
          :ets.lookup(:truth_last_results, {room_id, room.current_round}) != [] ->
            "results"

          :ets.lookup(:truth_round_data, {room_id, room.current_round}) != [] ->
            "answering"

          true ->
            nil
        end
    end
  end

  defp clear_truth_discussion_acks(room_id, round) do
    :ets.match_delete(:truth_discussion_ack, {{room_id, round, :_}, :_})
    :ok
  end

  @results_phase_seconds 45
  @min_questions_per_category 8
  @min_truth_options 4

  # Results-screen picks target the upcoming round; after advance, discussion/transition target current round.
  defp distortion_effect_round(room, "results") do
    min(room.current_round + 1, room.total_rounds)
  end

  defp distortion_effect_round(room, _), do: room.current_round

  defp schedule_auto_reveal_if_needed(room_id, round, question_id, socket) do
    connected_player_ids =
      room_id
      |> Game.round_active_players(round)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    committed_player_ids =
      room_id
      |> Game.get_round_commits(round)
      |> Enum.map(& &1.player_id)
      |> MapSet.new()

    all_committed =
      MapSet.size(connected_player_ids) > 0 and
        MapSet.equal?(connected_player_ids, committed_player_ids)

    if all_committed do
      auto_reveal_key = {:auto_reveal_scheduled, room_id, round}

      case :ets.insert_new(:round_scored, {auto_reveal_key, true}) do
        true ->
          IO.puts("✅ All connected players committed! Auto-revealing in 2 seconds...")
          short_end = System.system_time(:millisecond) + 3_000

          broadcast!(socket, "answering_timer_update", %{
            round: round,
            phase_ends_at_ms: short_end
          })

          Endpoint.broadcast("display:#{socket.assigns.room_code}", "display:answering_timer_update", %{
            round: round,
            phase_ends_at_ms: short_end
          })

          Process.send_after(self(), {:auto_reveal, round, question_id}, 2_000)

        false ->
          IO.puts("⏳ Auto-reveal already scheduled by another process")
      end
    end
  end

  defp schedule_results_auto_advance(room_id, round) do
    key = {:results_auto_advance_scheduled, room_id, round}

    if :ets.insert_new(:round_scored, {key, true}) do
      schedule_internal_message(room_id, {:auto_advance_round, room_id, round}, @results_phase_seconds * 1000)
    end
  end

  defp broadcast_game_state(room_id) do
    room = Game.get_room!(room_id)
    state = get_game_state(room)
    Endpoint.broadcast("game:#{room.code}", "game_state", state)
    state
  end

  defp broadcast_room_reset_to_lobby(room_id) do
    room = Game.get_room!(room_id)
    players = Game.list_players(room_id)
    mode = Game.room_mode(room)

    payload = %{
      state: "lobby",
      room_code: room.code,
      current_round: 0,
      total_rounds: room.total_rounds,
      players: format_players(players, mode)
    }

    Endpoint.broadcast("game:#{room.code}", "room_reset_to_lobby", payload)
    Endpoint.broadcast("display:#{room.code}", "display:room_reset_to_lobby", payload)
  end

  defp rematch_approved_payload(room_id, vote_count, votes) do
    room = Game.get_room!(room_id)
    players = Game.list_players(room_id)
    mode = Game.room_mode(room)

    %{
      message: "#{vote_count} players confirmed rematch.",
      state: "lobby",
      room_code: room.code,
      voters: MapSet.to_list(votes),
      players: format_players(players, mode)
    }
  end

  defp purge_distortions_for_round(room_id, round) do
    :ets.lookup(:truth_distortions, room_id)
    |> Enum.filter(fn
      {^room_id, ^round, _, _, _} -> true
      _ -> false
    end)
    |> Enum.each(&:ets.delete_object(:truth_distortions, &1))
  end

  defp rematch_vote_payload(room_id) do
    votes =
      case :ets.lookup(:rematch_votes, room_id) do
        [] -> MapSet.new()
        [{^room_id, v}] -> v
      end

    declined =
      case :ets.lookup(:rematch_declined, room_id) do
        [] -> MapSet.new()
        [{^room_id, d}] -> d
      end

    total_players = rematch_snapshot_total(room_id)

    %{
      vote_count: MapSet.size(votes),
      declined_count: MapSet.size(declined),
      total_players: total_players,
      voters: MapSet.to_list(votes),
      declined: MapSet.to_list(declined)
    }
  end

  defp question_time_limit(room) do
    # Classic mode has fixed 15s in mock questions; Truth mode is per-question and stored in commit_windows.
    if Game.room_mode(room) == "truth_collapse" do
      case Game.commit_window(room.id, room.current_round) do
        {:ok, %{time_limit_s: s}} when is_integer(s) -> s
        _ -> 15
      end
    else
      15
    end
  end

  defp prepare_truth_round_question(room, round) do
    base_question = generate_question_for_mode(room, round)
    {question, effects} = apply_distortions_for_round(room.id, round, base_question)
    conn = count_connected(room.id)
    question = ensure_truth_question_option_capacity(question, conn + 1)
    question = resize_truth_options_for_players(question, conn)
    {question, effects}
  end

  defp prepare_truth_round_base(room, round) do
    base_question = generate_question_for_mode(room, round)
    conn = count_connected(room.id)
    question = ensure_truth_question_option_capacity(base_question, conn + 1)
    question = resize_truth_options_for_players(question, conn)

    effects = %{
      log: [],
      blind_targets: MapSet.new(),
      category_timeline: [Map.get(question, :category)],
      remove_targets: %{}
    }

    {question, effects}
  end

  defp start_truth_round_flow(socket, room, round) do
    # "Preparing/discussion" phase duration
    discussion_seconds = 15

    # Ensure stale dedupe flags from previous runs cannot block answering transition.
    :ets.delete(:round_scored, {{:truth_q_started, room.id, round}, true})
    clear_truth_discussion_acks(room.id, round)

    {question, effects} = prepare_truth_round_question(room, round)

    set_truth_active_category(room.id, question.category)

    :ets.insert(:truth_room_phase, {room.id, %{round: round, phase: "discussion"}})
    :ets.insert(:truth_discussion_mono, {room.id, System.monotonic_time(:millisecond)})

    :ets.insert(:truth_round_data, {{room.id, round}, %{question: question, effects: effects}})

    timeline_labels = Enum.map(effects.category_timeline, &truth_category_label/1)

    # Discussion phase: do not leak question text to the host screen (only theme + meta).
    display_payload = %{
      round: round,
      discussion_seconds: discussion_seconds,
      mode: "truth_collapse",
      question: nil,
      discussion_only: true,
      option_count: length(question.options),
      applied_distortions: effects.log,
      blind_targets: MapSet.to_list(effects.blind_targets),
      shuffle_targets: MapSet.to_list(effects.blind_targets),
      category: question.category,
      category_label: truth_category_label(question.category),
      category_timeline: effects.category_timeline,
      category_timeline_labels: timeline_labels
    }

    phase_ends_at_ms = System.system_time(:millisecond) + discussion_seconds * 1000

    player_payload = %{
      round: round,
      discussion_seconds: discussion_seconds,
      phase_ends_at_ms: phase_ends_at_ms,
      mode: "truth_collapse",
      question_id: question.id,
      category: question.category,
      category_label: truth_category_label(question.category),
      category_timeline: effects.category_timeline,
      category_timeline_labels: timeline_labels,
      options: Enum.map(question.options, & &1.id)
    }

    display_payload = Map.put(display_payload, :phase_ends_at_ms, phase_ends_at_ms)

    broadcast_to_both(socket, "discussion_started", player_payload, "display:discussion_started", display_payload)

    schedule_internal_message(room.id, {:truth_begin_answering, room.id, round}, discussion_seconds * 1000)
  end

  # Broadcast to both player channel (game:*) and display channel (display:*)
  defp broadcast_to_both(socket, player_event, player_payload, display_event, display_payload) do
    server_ts = System.system_time(:millisecond)
    player_payload = if is_map(player_payload), do: Map.put_new(player_payload, :server_timestamp_ms, server_ts), else: player_payload
    display_payload = if is_map(display_payload), do: Map.put_new(display_payload, :server_timestamp_ms, server_ts), else: display_payload

    # Broadcast to player channel (minimal info)
    broadcast!(socket, player_event, player_payload)

    # Broadcast to display channel (full info)
    room_code = socket.assigns.room_code
    Endpoint.broadcast("display:#{room_code}", display_event, display_payload)
  end

  defp score_round_internal(room_id, round, question_id, socket) do
    room = Game.get_room!(room_id)
    if Game.room_mode(room) == "truth_collapse" do
      truth_score_round(room, round, question_id, socket)
    else
      # Get the current question to find correct answer
      question = generate_mock_question(round)

      IO.puts("🎯 Scoring round #{round}: expected question_id=#{question_id}, generated question_id=#{question.id}, correct=#{question.correct}")

      if question.id == question_id do
        # Get all commits for this round
        commits = Game.get_round_commits(room_id, round)

        IO.puts("🎯 Auto-reveal scoring round #{round} with #{length(commits)} commits")

        # Score each commit (only if not already scored)
        scores = Enum.map(commits, fn commit ->
          # Check if this commit has already been scored
          if commit.points_awarded && commit.points_awarded > 0 do
            IO.puts("⚠️ Commit for player #{commit.player_id} already scored, skipping")
            %{
              player_id: commit.player_id,
              is_correct: commit.is_correct || false,
              points: commit.points_awarded || 0,
              answer: commit_text(commit)
            }
          else
            # The answer was already stored when committing
            # We just need to check if it matches the correct answer
            is_correct = commit_text(commit) == question.correct
            points = if is_correct, do: 100, else: 0

            # Mark commit as scored
            save_scored_commit(commit, is_correct, points, room_id, round)

            # Update player score only if correct
            if is_correct do
              Game.update_player_score(commit.player_id, points)
            end

            %{
              player_id: commit.player_id,
              is_correct: is_correct,
              points: points,
              answer: commit_text(commit)
            }
          end
        end)

        players = Game.list_players(room_id)

        # Broadcast scores: full to display, minimal to players
        display_scored_payload = %{
          round: round,
          scores: scores,
          leaderboard: format_leaderboard(players),
          correct_answer: question.correct,
          question: question
        }
        player_scored_payload = %{
          round: round,
          message: "Look at the screen for results!"
        }
        broadcast_to_both(socket, "round_scored", player_scored_payload, "display:round_scored", display_scored_payload)

        # Auto-advance to next round after 5 seconds (show results)
        room = Game.get_room!(room_id)
        schedule_internal_message(room_id, {:auto_advance_round, room_id, room.current_round}, 5_000)
      else
        IO.puts("❌ ERROR: Question ID mismatch in force scoring! Expected #{question_id}, got #{question.id}. Round #{round} may have wrong question.")
        # Still score with the generated question to prevent game from stalling
        commits = Game.get_round_commits(room_id, round)
        IO.puts("⚠️ Force scoring anyway with generated question (ID: #{question.id}, correct: #{question.correct})")

        scores = Enum.map(commits, fn commit ->
          if commit.points_awarded && commit.points_awarded > 0 do
            %{
              player_id: commit.player_id,
              is_correct: commit.is_correct || false,
              points: commit.points_awarded || 0,
              answer: commit_text(commit)
            }
          else
            is_correct = commit_text(commit) == question.correct
            points = if is_correct, do: 100, else: 0

            save_scored_commit(commit, is_correct, points, room_id, round)

            if is_correct do
              Game.update_player_score(commit.player_id, points)
            end

            %{
              player_id: commit.player_id,
              is_correct: is_correct,
              points: points,
              answer: commit_text(commit)
            }
          end
        end)

        players = Game.list_players(room_id)
        display_scored_payload = %{
          round: round,
          scores: scores,
          leaderboard: format_leaderboard(players),
          correct_answer: question.correct,
          question: question
        }
        player_scored_payload = %{
          round: round,
          message: "Look at the screen for results!"
        }
        broadcast_to_both(socket, "round_scored", player_scored_payload, "display:round_scored", display_scored_payload)

        room = Game.get_room!(room_id)
        schedule_internal_message(room_id, {:auto_advance_round, room_id, room.current_round}, 5_000)
      end

      {:noreply, socket}
    end
  end

  defp score_round_force(room_id, round, question_id, socket) do
    room = Game.get_room!(room_id)
    if Game.room_mode(room) == "truth_collapse" do
      truth_score_round(room, round, question_id, socket)
    else
      # Force scoring even if not all players committed
      # This ensures game continues even if players don't answer
      question = generate_mock_question(round)

      IO.puts("⏰ Force scoring round #{round}: expected question_id=#{question_id}, generated question_id=#{question.id}, correct=#{question.correct}")

      if question.id == question_id do
        IO.puts("✅ Question ID matches! Force scoring with correct answer: #{question.correct}")
        commits = Game.get_round_commits(room_id, round)

        IO.puts("⏰ Force auto-reveal scoring round #{round} with #{length(commits)} commits")

        # Score only the players who committed (only if not already scored)
        scores = Enum.map(commits, fn commit ->
          # Check if this commit has already been scored
          if commit.points_awarded && commit.points_awarded > 0 do
            IO.puts("⚠️ Commit for player #{commit.player_id} already scored, skipping")
            %{
              player_id: commit.player_id,
              is_correct: commit.is_correct || false,
              points: commit.points_awarded || 0,
              answer: commit_text(commit)
            }
          else
            is_correct = commit_text(commit) == question.correct
            points = if is_correct, do: 100, else: 0

            # Mark commit as scored
            save_scored_commit(commit, is_correct, points, room_id, round)

            # Update player score only if correct
            if is_correct do
              Game.update_player_score(commit.player_id, points)
            end

            %{
              player_id: commit.player_id,
              is_correct: is_correct,
              points: points,
              answer: commit_text(commit)
            }
          end
        end)

        players = Game.list_players(room_id)

        # Broadcast scores: full to display, minimal to players
        display_scored_payload = %{
          round: round,
          scores: scores,
          leaderboard: format_leaderboard(players),
          correct_answer: question.correct,
          question: question
        }
        player_scored_payload = %{
          round: round,
          message: "Look at the screen for results!"
        }
        broadcast_to_both(socket, "round_scored", player_scored_payload, "display:round_scored", display_scored_payload)

        # Auto-advance to next round after 5 seconds (show results)
        room = Game.get_room!(room_id)
        schedule_internal_message(room_id, {:auto_advance_round, room_id, room.current_round}, 5_000)
      else
        IO.puts("❌ ERROR: Question ID mismatch in force scoring! Expected #{question_id}, got #{question.id}. Round #{round} may have wrong question.")
        # Still score with the generated question to prevent game from stalling
        commits = Game.get_round_commits(room_id, round)
        IO.puts("⚠️ Force scoring anyway with generated question (ID: #{question.id}, correct: #{question.correct})")

        scores = Enum.map(commits, fn commit ->
          if commit.points_awarded && commit.points_awarded > 0 do
            %{
              player_id: commit.player_id,
              is_correct: commit.is_correct || false,
              points: commit.points_awarded || 0,
              answer: commit_text(commit)
            }
          else
            is_correct = commit_text(commit) == question.correct
            points = if is_correct, do: 100, else: 0

            save_scored_commit(commit, is_correct, points, room_id, round)

            if is_correct do
              Game.update_player_score(commit.player_id, points)
            end

            %{
              player_id: commit.player_id,
              is_correct: is_correct,
              points: points,
              answer: commit_text(commit)
            }
          end
        end)

        players = Game.list_players(room_id)
        display_scored_payload = %{
          round: round,
          scores: scores,
          leaderboard: format_leaderboard(players),
          correct_answer: question.correct,
          question: question
        }
        player_scored_payload = %{
          round: round,
          message: "Look at the screen for results!"
        }
        broadcast_to_both(socket, "round_scored", player_scored_payload, "display:round_scored", display_scored_payload)

        room = Game.get_room!(room_id)
        schedule_internal_message(room_id, {:auto_advance_round, room_id, room.current_round}, 5_000)
      end

      {:noreply, socket}
    end
  end

  defp reset_room_for_rematch(room_id) do
    if Game.cache_enabled?() do
      # Reset room state
      room = Game.get_room!(room_id)
      updated_room = %{room | state: "lobby", current_round: 0, started_at: nil, updated_at: DateTime.utc_now()}
      :ets.insert(:room_cache, {updated_room.code, updated_room})
      :ets.insert(:room_cache, {updated_room.id, updated_room})

      # Reset all player scores
      players = Game.list_players(room_id)
      Enum.each(players, fn player ->
        updated_player = %{player | score: 0, updated_at: DateTime.utc_now()}
        :ets.insert(:player_cache, {player.id, updated_player})
      end)
      # Re-cache updated players in room_players_cache
      reset_players = Enum.map(players, fn player -> %{player | score: 0} end)
      :ets.insert(:room_players_cache, {room_id, reset_players})

      # Clean up all answer commits for this room
      :ets.match_delete(:answer_commits_cache, {{room_id, :_}, :_})

      clear_truth_runtime_for_new_game(room_id, players)
    else
      # Reset room state
      room = Game.get_room!(room_id)

      room
      |> Ecto.Changeset.change(%{
        state: "lobby",
        current_round: 0,
        started_at: nil
      })
      |> Repo.update()

      # Reset all player scores
      players = Game.list_players(room_id)
      Enum.each(players, fn player ->
        player
        |> Ecto.Changeset.change(%{score: 0})
        |> Repo.update()
      end)

      # Clean up all answer commits for this room
      import Ecto.Query
      alias VnParty.Game.AnswerCommit

      AnswerCommit
      |> where([c], c.room_id == ^room_id)
      |> Repo.delete_all()

      clear_truth_runtime_for_new_game(room_id, players)
    end
  end

  defp rematch_snapshot_ids(room_id) do
    case :ets.lookup(:rematch_snapshot, room_id) do
      [{^room_id, ids}] when is_struct(ids, MapSet) -> ids
      _ ->
        Game.list_players(room_id)
        |> Enum.filter(& &1.connected)
        |> Enum.map(& &1.id)
        |> MapSet.new()
    end
  end

  defp rematch_snapshot_total(room_id), do: MapSet.size(rematch_snapshot_ids(room_id))

  defp clear_rematch_state(room_id) do
    :ets.delete(:rematch_votes, room_id)
    :ets.delete(:rematch_declined, room_id)
    :ets.delete(:rematch_snapshot, room_id)
  end

  defp clear_truth_runtime_for_new_game(room_id, players) do
    # Clear old truth-round runtime state so rematch/new game starts clean.
    :ets.match_delete(:round_scored, {{room_id, :_}, :_})
    :ets.match_delete(:round_scored, {{:auto_reveal_scheduled, room_id, :_}, :_})
    :ets.match_delete(:round_scored, {{{:truth_q_started, room_id, :_}, true}, :_})
    :ets.match_delete(:round_scored, {{:truth_q_started, room_id, :_}, :_})

    :ets.match_delete(:truth_round_data, {{room_id, :_}, :_})
    :ets.match_delete(:truth_last_results, {{room_id, :_}, :_})
    :ets.match_delete(:truth_answering_mono, {{room_id, :_}, :_})
    :ets.match_delete(:truth_predictions, {{room_id, :_, :_}, :_})
    :ets.match_delete(:truth_results_ack, {{room_id, :_, :_}, :_})
    :ets.match_delete(:truth_discussion_ack, {{room_id, :_, :_}, :_})
    :ets.match_delete(:truth_question_history, {{room_id, :_}, :_})
    :ets.match_delete(:truth_fake_locks, {{room_id, :_, :_}, :_})
    :ets.match_delete(:truth_inject_preview, {{room_id, :_}, :_})

    :ets.delete(:truth_distortions, room_id)
    :ets.delete(:truth_room_phase, room_id)
    :ets.delete(:truth_discussion_mono, room_id)
    :ets.delete(:truth_active_category, room_id)
    DistortionRules.clear_room(room_id)

    Enum.each(players, fn player ->
      :ets.delete(:truth_player_stats, player.id)
    end)
  end

  defp maybe_register_rematch_disconnect_vote(socket) do
    room_id = socket.assigns[:room_id]
    player_id = socket.assigns[:player_id]

    cond do
      is_nil(room_id) or is_nil(player_id) ->
        :ok

      :ets.lookup(:rematch_snapshot, room_id) == [] ->
        :ok

      true ->
        snapshot_ids = rematch_snapshot_ids(room_id)

        if MapSet.member?(snapshot_ids, player_id) do
          votes =
            case :ets.lookup(:rematch_votes, room_id) do
              [{^room_id, set}] when is_struct(set, MapSet) -> set
              _ -> MapSet.new()
            end

          declined =
            case :ets.lookup(:rematch_declined, room_id) do
              [{^room_id, set}] when is_struct(set, MapSet) -> set
              _ -> MapSet.new()
            end

          if not MapSet.member?(votes, player_id) and not MapSet.member?(declined, player_id) do
            :ets.insert(:rematch_declined, {room_id, MapSet.put(declined, player_id)})
            PubSub.broadcast(VnParty.PubSub, "room:#{room_id}:internal", {:check_rematch, room_id})
          end
        end
    end
  end

  defp get_game_state(room) do
    players = Game.list_players(room.id)
    mode = Game.room_mode(room)

    %{
      room_code: room.code,
      mode: mode,
      state: room.state,
      current_round: room.current_round,
      total_rounds: room.total_rounds,
      players: format_players(players, mode),
      started_at: room.started_at,
      truth_resume: build_truth_resume(room)
    }
  end

  defp count_connected(room_id) do
    room_id |> Game.list_players() |> Enum.count(& &1.connected)
  end

  defp build_player_question_payload(room_id, question, effects) do
    all_ids = Enum.map(question.options, & &1.id)
    remove_targets = Map.get(effects, :remove_targets, %{})
    shuffle_targets = MapSet.to_list(effects.blind_targets)

    personalized_options =
      room_id
      |> Game.list_players()
      |> Enum.into(%{}, fn p ->
        hidden = Map.get(remove_targets, p.id, [])
        {p.id, Enum.reject(all_ids, &(&1 in hidden))}
      end)

    %{
      id: question.id,
      options: all_ids,
      personalized_options: personalized_options,
      time_limit: question.time_limit,
      shuffle_targets: shuffle_targets,
      remove_targets: remove_targets
    }
  end

  # Truth Collapse: option count follows connected players (capped by available options in the pool).
  defp resize_truth_options_for_players(q, connected_n) when connected_n < 0, do: q

  defp resize_truth_options_for_players(%{options: []} = q, _), do: q

  defp resize_truth_options_for_players(%{options: options} = q, connected_n) do
    # Target: one option per connected player + 1, floor at @min_truth_options, cap at available
    want = connected_n + 1
    want = max(want, @min_truth_options)
    want = min(want, length(options))
    correct_ids = if is_list(q.correct), do: q.correct, else: [q.correct]

    # Injected (fake) options are protected — always kept alongside the correct answer
    injected_ids =
      case Map.get(q, :injected_option_ids) do
        ids when is_list(ids) -> ids
        _ -> []
      end

    protected_ids = MapSet.new(correct_ids ++ injected_ids)
    protected = Enum.filter(options, fn o -> MapSet.member?(protected_ids, o.id) end)
    wrongs = Enum.reject(options, fn o -> MapSet.member?(protected_ids, o.id) end)

    # Increase want to accommodate injected options so we don't squeeze out regular wrongs
    want = max(want, length(protected) + 1)
    want = min(want, length(options))

    need_wrong = max(0, want - length(protected))
    keep_ids =
      (Enum.map(protected, & &1.id) ++ Enum.map(Enum.take(wrongs, need_wrong), & &1.id))
      |> MapSet.new()

    ordered = Enum.filter(options, fn o -> MapSet.member?(keep_ids, o.id) end)
    %{q | options: ordered}
  end

  defp ensure_truth_question_option_capacity(%{options: options} = q, want) do
    want = max(want, @min_truth_options)

    if length(options) >= want do
      q
    else
      pool = truth_question_pools()
      cat = Map.get(q, :category)
      cat_questions = Map.get(pool, cat, [])

      existing_texts =
        options
        |> Enum.map(&String.downcase(String.trim(&1.text)))
        |> MapSet.new()

      candidates =
        cat_questions
        |> Enum.flat_map(& &1.options)
        |> Enum.uniq_by(&String.downcase(String.trim(&1.text)))
        |> Enum.reject(fn o -> MapSet.member?(existing_texts, String.downcase(String.trim(o.text))) end)

      need = want - length(options)
      extras = Enum.take(candidates, need)

      used_ids = Enum.map(options, & &1.id)

      extras =
        Enum.reduce(extras, {[], used_ids}, fn o, {acc, ids} ->
          nid = next_option_id(ids)
          {[Map.put(o, :id, nid) | acc], ids ++ [nid]}
        end)
        |> elem(0)
        |> Enum.reverse()

      all = options ++ extras
      # Keep stable A,B,C,D... ordering even after removals/refills.
      %{q | options: Enum.sort_by(all, & &1.id)}
    end
  end

  @doc false
  def build_truth_resume(room) do
    room_id = room.id

    with "truth_collapse" <- Game.room_mode(room),
         "round_start" <- room.state,
         true <- room.current_round > 0,
         [{^room_id, meta}] <- :ets.lookup(:truth_room_phase, room_id) do
      round = room.current_round
      base = %{round: meta.round, phase: meta.phase}

      case meta.phase do
        "transition" ->
          Map.put(base, :message, "Next round is loading…")

        "discussion" ->
          resume_truth_discussion(room_id, round, base)

        "answering" ->
          resume_truth_answering(room_id, round, base)

        "results" ->
          resume_truth_results(room_id, round, base)

        _ ->
          nil
      end
    else
      _ -> nil
    end
  end

  defp resume_truth_discussion(room_id, round, base) do
    case :ets.lookup(:truth_round_data, {room_id, round}) do
      [{{^room_id, ^round}, %{question: q, effects: eff}}] ->
        conn = count_connected(room_id)
        q2 = resize_truth_options_for_players(q, conn)

        started_ms =
          case :ets.lookup(:truth_discussion_mono, room_id) do
            [{^room_id, t}] -> t
            [] -> System.monotonic_time(:millisecond)
          end

        elapsed_sec = div(System.monotonic_time(:millisecond) - started_ms, 1000)
        left = max(0, 15 - elapsed_sec)

        Map.merge(base, %{
          discussion_seconds: left,
          phase_ends_at_ms: System.system_time(:millisecond) + left * 1000,
          question_id: q2.id,
          category: q2.category,
          category_label: truth_category_label(q2.category),
          category_timeline: eff.category_timeline,
          category_timeline_labels: Enum.map(eff.category_timeline, &truth_category_label/1),
          options: Enum.map(q2.options, & &1.id),
          shuffle_preview: MapSet.to_list(eff.blind_targets)
        })

      _ ->
        base
    end
  end

  defp resume_truth_answering(room_id, round, base) do
    case :ets.lookup(:truth_round_data, {room_id, round}) do
      [{{^room_id, ^round}, %{question: q, effects: eff}}] ->
        conn = count_connected(room_id)
        q2 = resize_truth_options_for_players(q, conn)
        :ets.insert(:truth_round_data, {{room_id, round}, %{question: q2, effects: eff}})

        started_ms =
          case :ets.lookup(:truth_answering_mono, {room_id, round}) do
            [{{^room_id, ^round}, t}] -> t
            [] -> System.monotonic_time(:millisecond)
          end

        elapsed_sec = div(System.monotonic_time(:millisecond) - started_ms, 1000)
        time_left = max(0, q2.time_limit - elapsed_sec)

        disp =
          Map.merge(q2, %{
            shuffle_targets: MapSet.to_list(eff.blind_targets),
            category_label: truth_category_label(Map.get(q2, :category)),
            applied_distortions: eff.log,
            merged_realities_active: merge_realities_used?(room_id, round)
          })

        Map.merge(base, %{
          time_left: time_left,
          display_question: disp,
          current_question:
            build_player_question_payload(room_id, q2, eff)
            |> Map.put(:time_limit, q2.time_limit)
        })

      _ ->
        base
    end
  end

  defp resume_truth_results(room_id, round, base) do
    ends_at = System.system_time(:millisecond) + @results_phase_seconds * 1000

    case :ets.lookup(:truth_last_results, {room_id, round}) do
      [{{^room_id, ^round}, snap}] ->
        Map.merge(base, Map.merge(snap, %{phase_ends_at_ms: ends_at, results_seconds: @results_phase_seconds}))

      [] ->
        Map.merge(base, %{phase_ends_at_ms: ends_at, results_seconds: @results_phase_seconds})
    end
  end

  defp format_players(players, mode \\ "classic") do
    Enum.map(players, fn player ->
      truth = if mode == "truth_collapse", do: get_truth_stats(player.id), else: %{tp: 0, di: 0, ps: 0, charges: 0}
      %{
        id: player.id,
        nickname: player.nickname,
        score: player.score,
        connected: player.connected,
        is_host: player.is_host,
        status: if(player.connected, do: "online", else: "absent"),
        truth_points: truth.tp,
        distortion_impact: truth.di,
        prediction_score: truth.ps,
        distortion_charges: truth.charges
      }
    end)
  end

  defp format_leaderboard(players) do
    Enum.map(players, fn player ->
      %{
        player_id: player.id,
        nickname: player.nickname,
        score: player.score
      }
    end)
  end

  defp init_truth_stats(players, reset) do
    Enum.each(players, fn player ->
      defaults = %{tp: 0, di: 0, ps: 0, charges: 0}

      case :ets.lookup(:truth_player_stats, player.id) do
        [] ->
          :ets.insert(:truth_player_stats, {player.id, defaults})

        _ when reset ->
          :ets.insert(:truth_player_stats, {player.id, defaults})

        _ ->
          :ok
      end
    end)
  end

  defp get_truth_stats(player_id) do
    case :ets.lookup(:truth_player_stats, player_id) do
      [{^player_id, stats}] -> stats
      [] ->
        defaults = %{tp: 0, di: 0, ps: 0, charges: 0}
        :ets.insert(:truth_player_stats, {player_id, defaults})
        defaults
    end
  end

  defp get_player_used_powers(room_id, player_id) do
    powers = ~w(remove_option swap_category force_blind inject_fake_option merge_realities)
    Enum.into(powers, %{}, fn action ->
      case :ets.lookup(:distortion_usage, {room_id, player_id, action}) do
        [{_, n}] -> {action, n}
        _ -> {action, 0}
      end
    end)
  end

  defp update_truth_stats(player_id, fun) do
    current = get_truth_stats(player_id)
    updated = fun.(current)
    :ets.insert(:truth_player_stats, {player_id, updated})
    updated
  end

  defp build_option_counts(commits) do
    commits
    |> Enum.map(fn c ->
      answer = Game.commit_answer_text(c) || c.answer
      {answer, c}
    end)
    |> Enum.reject(fn {answer, _} -> is_nil(answer) or answer == "" end)
    |> Enum.reduce(%{}, fn {answer, _c}, acc -> Map.update(acc, answer, 1, &(&1 + 1)) end)
    |> Enum.sort_by(fn {_opt, count} -> -count end)
    |> Enum.into(%{})
  end

  defp commit_text(commit), do: Game.commit_answer_text(commit) || commit.answer

  defp build_prediction_counts(room_id, round) do
    :ets.tab2list(:truth_predictions)
    |> Enum.filter(fn
      {{rid, r, _pid}, _opt} when rid == room_id and r == round -> true
      _ -> false
    end)
    |> Enum.reduce(%{}, fn {{_, _, _}, option_id}, acc ->
      Map.update(acc, option_id, 1, &(&1 + 1))
    end)
    |> Enum.sort_by(fn {_opt, count} -> -count end)
    |> Enum.into(%{})
  end

  defp apply_distortions_for_round(room_id, round, question) do
    player_ids = room_id |> Game.list_players() |> Enum.map(& &1.id)
    conn = count_connected(room_id)

    VnParty.TruthDistortionApply.apply_for_round(room_id, round, question,
      swap_fn: &generate_truth_question_from_category/4,
      category_picker: &pick_swap_category/2,
      connected_player_ids: player_ids,
      resize_fn: fn q ->
        q
        |> ensure_truth_question_option_capacity(conn + 1)
        |> resize_truth_options_for_players(conn)
      end
    )
  end

  defp pick_swap_category(question, requested) do
    categories = truth_question_pools() |> Map.keys() |> Enum.sort()

    current =
      case question do
        %{category: c} when is_binary(c) -> c
        _ -> nil
      end

    cond do
      is_binary(requested) and requested in categories ->
        requested

      true ->
        pool = Enum.reject(categories, fn c -> c == current end)
        pool = if pool == [], do: categories, else: pool
        Enum.at(pool, :rand.uniform(length(pool)) - 1)
    end
  end

  defp truth_category_label("general"), do: "Kiến Thức Chung"
  defp truth_category_label("weird_facts"), do: "Sự Thật Kỳ Lạ"
  defp truth_category_label("social_stats"), do: "Xã Hội & Thống Kê"
  defp truth_category_label("science_lite"), do: "Khoa Học Vui"
  defp truth_category_label("pop_culture"), do: "Văn Hóa Đại Chúng"
  defp truth_category_label("history"), do: "Lịch Sử"
  defp truth_category_label("geography"), do: "Địa Lý"
  defp truth_category_label("food_culture"), do: "Ẩm Thực & Văn Hóa"
  defp truth_category_label("sports_lite"), do: "Thể Thao Vui"
  defp truth_category_label("technology"), do: "Công Nghệ"
  defp truth_category_label(other) when is_binary(other), do: String.replace(other, "_", " ") |> String.capitalize()
  defp truth_category_label(_), do: "Không Rõ"

  defp merge_realities_used?(room_id, round) do
    prior_round = round - 1
    :ets.lookup(:truth_distortions, room_id)
    |> Enum.any?(fn
      {^room_id, ^prior_round, _pid, "merge_realities", _payload} -> true
      _ -> false
    end)
  end

  defp merge_realities_used_for_round(room_id, round) do
    :ets.lookup(:truth_distortions, room_id)
    |> Enum.any?(fn
      {^room_id, ^round, _pid, "merge_realities", _payload} -> true
      _ -> false
    end)
  end

  defp distortion_cost("remove_option"), do: 2
  defp distortion_cost("swap_category"), do: 2
  defp distortion_cost("force_blind"), do: 3
  defp distortion_cost("inject_fake_option"), do: 4
  defp distortion_cost("merge_realities"), do: 4
  defp distortion_cost(_), do: 99

  defp validate_distortion_payload("remove_option", payload, room, _player_id) do
    target = Map.get(payload, "target_player_id", Map.get(payload, :target_player_id))
    room_player_ids = room.id |> Game.list_players() |> Enum.map(& &1.id)

    cond do
      not is_binary(target) or target == "" ->
        {:error, "Please select a target player"}

      target not in room_player_ids ->
        {:error, "Target player is not in this room"}

      true ->
        {:ok, %{"target_player_id" => target}}
    end
  end

  defp validate_distortion_payload("inject_fake_option", payload, _room, _player_id) do
    raw = Map.get(payload, "fake_text", Map.get(payload, :fake_text, ""))
    txt = sanitize_fake_text(raw)

    cond do
      txt == "" ->
        {:error, "Please enter a fake answer"}

      String.length(txt) < 3 and not Regex.match?(~r/^\d+$/, txt) ->
        {:error, "Fake answer is too short (min 3 chars, or a number like 5)"}

      String.length(txt) > 60 ->
        {:error, "Fake answer is too long (max 60 chars)"}
      contains_prohibited_text?(txt) -> {:error, "That text is not allowed by room safety filter"}
      true -> {:ok, %{"fake_text" => txt}}
    end
  end

  defp validate_distortion_payload("force_blind", payload, room, player_id) do
    target = Map.get(payload, "target_player_id", Map.get(payload, :target_player_id))
    connected_ids = room.id |> Game.list_players() |> Enum.filter(& &1.connected) |> Enum.map(& &1.id)

    cond do
      not is_binary(target) or target == "" ->
        {:ok, %{"target_player_id" => "__all_others__"}}

      target == player_id ->
        {:error, "Cannot force-blind yourself"}

      target not in connected_ids ->
        {:error, "Target player is not connected"}

      true ->
        {:ok, %{"target_player_id" => target}}
    end
  end

  defp validate_distortion_payload("merge_realities", payload, room, _player_id) do
    if room.current_round >= room.total_rounds do
      {:error, "Merge realities has no effect on the final round"}
    else
      {:ok, payload}
    end
  end

  defp validate_distortion_payload(_action, payload, _room, _player_id), do: {:ok, payload}

  defp sanitize_fake_text(txt) when is_binary(txt) do
    txt
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp sanitize_fake_text(_), do: ""

  defp contains_prohibited_text?(txt) do
    lower = String.downcase(txt)

    banned = [
      "fuck", "fucking", "shit", "bitch", "asshole", "cunt", "dick",
      "nigger", "rape", "kill yourself", "suicide",
      "địt", "đụ", "đéo", "đĩ", "đĩ mẹ", "cặc", "lồn", "buồi", "óc chó"
    ]

    has_banned = Enum.any?(banned, &String.contains?(lower, &1))
    has_url = String.match?(lower, ~r/https?:\/\/|www\./)
    has_contact = String.match?(lower, ~r/\b\d{8,}\b|@/)
    has_sql = String.match?(lower, ~r/--|\/\*|\*\/|drop\s+table|select\s+\*/)

    has_banned or has_url or has_contact or has_sql
  end

  defp generate_question_for_mode(room, round) do
    if Game.room_mode(room) == "truth_collapse" do
      q = generate_truth_question(room, round)
      if round == room.total_rounds do
        apply_final_collapse_effects(q)
      else
        q
      end
    else
      generate_mock_question(round)
    end
  end

  defp truth_score_round(room, round, _question_id, socket) do
    room_id = room.id
    score_key = {:truth_score_broadcast, room_id, round}

    if not :ets.insert_new(:round_scored, {score_key, true}) do
      {:noreply, socket}
    else
    truth_clear_results_acks(room_id, round)

    {question, effects} =
      case :ets.lookup(:truth_round_data, {room_id, round}) do
        [{{^room_id, ^round}, %{question: q, effects: eff}}] ->
          {q, eff}

        _ ->
          IO.puts("⚠️ truth_score_round: missing stored question for round #{round}, regenerating")
          {generate_question_for_mode(room, round), %{fake_entries: []}}
      end
    commits = Game.get_round_commits(room_id, round)
    players = Game.list_players(room_id)
    connected_players = Enum.filter(players, & &1.connected)
    counts = build_option_counts(commits)
    sorted = Enum.sort_by(counts, fn {_opt, count} -> -count end)
    stable_round = length(sorted) <= 1
    merged_realities = merge_realities_used_for_round(room_id, round)
    realities = if merged_realities, do: ["MERGED"], else: top_realities(sorted)
    top2 = Enum.take(sorted, 2) |> Enum.map(&elem(&1, 0))

    # Prediction scoring
    Enum.each(connected_players, fn p ->
      key = {room_id, round, p.id}
      case :ets.lookup(:truth_predictions, key) do
        [{^key, predicted}] ->
          bonus =
            if sorted != [] and predicted == elem(hd(sorted), 0) do
              50
            else
              if predicted in top2, do: 20, else: 0
            end
          if bonus > 0, do: update_truth_stats(p.id, fn s -> %{s | ps: s.ps + bonus} end)
        [] -> :ok
      end
    end)

    correct_options = if is_list(question.correct), do: question.correct, else: [question.correct]
    true_reality = Enum.find(realities, fn option -> option in correct_options end)
    beaten_count = Enum.count(commits, fn c -> commit_text(c) not in correct_options end)

    score_rows =
      Enum.map(commits, fn commit ->
        # Hash tampering detection in truth mode too.
        {:ok, commit} = Game.flag_hash_tampering_if_any(commit)

        is_true = if merged_realities, do: commit_text(commit) in correct_options, else: commit_text(commit) == true_reality
        if is_true do
          base = 100 + beaten_count * 20
          tp_gain = if stable_round, do: trunc(base * 1.1), else: base
          update_truth_stats(commit.player_id, fn s -> %{s | tp: s.tp + tp_gain} end)
          Game.update_player_score(commit.player_id, tp_gain)
          %{player_id: commit.player_id, answer: commit_text(commit), in_true_reality: true, tp_gain: tp_gain, distortion_gain: 0}
        else
          stats = update_truth_stats(commit.player_id, fn s -> %{s | charges: min(5, s.charges + 1)} end)
          %{player_id: commit.player_id, answer: commit_text(commit), in_true_reality: false, tp_gain: 0, distortion_gain: 1, charges: stats.charges}
        end
      end)

    # If other players picked a fake injected option, reward the distortion author.
    fake_entries = Map.get(effects, :fake_entries, [])
    Enum.each(fake_entries, fn e ->
      fooled =
        Enum.count(commits, fn c ->
          commit_text(c) == e.option_id and c.player_id != e.player_id
        end)

      if fooled > 0 do
        bonus_points = fooled * 40
        bonus_charges = min(fooled, 2)
        Game.update_player_score(e.player_id, bonus_points)
        update_truth_stats(e.player_id, fn s ->
          %{s | charges: min(5, s.charges + bonus_charges), di: s.di + fooled * 8}
        end)
      end
    end)

    players_after = Game.list_players(room_id)
    mode_leaderboard = format_truth_leaderboard(players_after)
    final_payload = %{
      round: round,
      mode: "truth_collapse",
      counts: counts,
      realities: realities,
      merged_realities: merged_realities,
      true_reality: true_reality,
      stable_round: stable_round,
      scores: score_rows,
      leaderboard: mode_leaderboard,
      correct_answer: question.correct,
      question: question
    }
    # Broadcast full payload to display; send lightweight payload to players but include mode and updated stats list
    stats_public =
      Enum.map(players_after, fn p ->
        s = get_truth_stats(p.id)
        used = get_player_used_powers(room_id, p.id)
        %{player_id: p.id, tp: s.tp, di: s.di, ps: s.ps, charges: s.charges, used_powers: used}
      end)

    results_ends_at = System.system_time(:millisecond) + @results_phase_seconds * 1000

    player_payload = %{
      round: round,
      mode: "truth_collapse",
      stats: stats_public,
      phase: "results",
      phase_ends_at_ms: results_ends_at,
      results_seconds: @results_phase_seconds
    }

    :ets.insert(:truth_room_phase, {room_id, %{round: round, phase: "results"}})

    :ets.insert(:truth_last_results, {
      {room_id, round},
      %{
        stats: stats_public,
        round: round,
        mode: "truth_collapse",
        display_round_scored: final_payload
      }
    })

    broadcast_to_both(socket, "round_scored", player_payload, "display:round_scored", final_payload)

    phase_payload = %{
      round: round,
      phase: "results",
      phase_ends_at_ms: results_ends_at,
      results_seconds: @results_phase_seconds,
      mode: "truth_collapse"
    }

    broadcast!(socket, "truth_results_phase", phase_payload)

    # Immediately sync "ready" counter so all clients show the same baseline.
    initial_progress = %{round: round, acked_count: 0, total: length(connected_players), acked_player_ids: []}
    broadcast_to_both(socket, "truth_results_progress", initial_progress, "display:truth_results_progress", initial_progress)

    schedule_results_auto_advance(room_id, round)
    {:noreply, socket}
    end
  end

  defp top_realities([]), do: []
  defp top_realities([{first_opt, _first_count} | rest]) do
    second_count =
      case rest do
        [] -> nil
        [{_, c} | _] -> c
      end

    base = [first_opt]
    if is_nil(second_count) do
      base
    else
      tied = Enum.filter(rest, fn {_opt, c} -> c == second_count end) |> Enum.map(&elem(&1, 0))
      Enum.take(base ++ tied, 3)
    end
  end

  defp format_truth_leaderboard(players) do
    Enum.map(players, fn p ->
      stats = get_truth_stats(p.id)
      final_score = stats.tp * 0.6 + stats.di * 0.3 + stats.ps * 0.1
      %{player_id: p.id, nickname: p.nickname, score: p.score, tp: stats.tp, di: stats.di, ps: stats.ps, final_score: final_score}
    end)
    |> Enum.sort_by(&(-&1.final_score))
  end

  defp init_truth_active_category(room_id) do
    pools = truth_question_pools()
    cats = Map.keys(pools) |> Enum.sort()
    cat = Enum.at(cats, :rand.uniform(length(cats)) - 1)
    :ets.insert(:truth_active_category, {room_id, cat})
  end

  defp get_truth_active_category(room_id) do
    case :ets.lookup(:truth_active_category, room_id) do
      [{^room_id, cat}] when is_binary(cat) -> cat
      _ -> nil
    end
  end

  defp set_truth_active_category(room_id, category) when is_binary(category) do
    :ets.insert(:truth_active_category, {room_id, category})
  end

  defp truth_clear_results_acks(room_id, round) do
    :ets.select_delete(:truth_results_ack, [
      {{{:"$1", :"$2", :"$3"}, :_},
       [
         {:andalso, {:==, {:const, room_id}, :"$1"}, {:==, {:const, round}, :"$2"}}
       ],
       [true]}
    ])
  end

  defp generate_truth_question(room, round) do
    generate_truth_question(room, round, nil)
  end

  # Peek at the next question WITHOUT writing to history.
  # Used by inject_fake_option to show a preview that matches the actual round.
  defp peek_next_truth_question(room, round) do
    pools = truth_question_pools()
    room_id = room.id

    category =
      case get_truth_active_category(room_id) do
        nil ->
          init_truth_active_category(room_id)
          get_truth_active_category(room_id)
        cat -> cat
      end

    cat = if Map.has_key?(pools, category), do: category, else: hd(Map.keys(pools) |> Enum.sort())
    questions = Map.fetch!(pools, cat)

    # Read history but don't write — identical logic to pick_truth_question(:sequential)
    history_key = {room_id, cat}
    used_ids =
      case :ets.lookup(:truth_question_history, history_key) do
        [{^history_key, ids}] when is_list(ids) -> ids
        _ -> []
      end

    used_set = MapSet.new(used_ids)
    available = Enum.reject(questions, fn q -> MapSet.member?(used_set, q.id) end)
    available = if available == [], do: questions, else: available
    selected = Enum.at(available, rem(round - 1, length(available)))

    selected
    |> ensure_question_min_options(cat)
    |> Map.put(:category, cat)
    |> Map.put(:time_limit, 120)
  end

  # forced_category: internal use (e.g. tests); otherwise use persisted room category from ETS
  defp generate_truth_question(room, round, forced_category) do
    room_id = room.id

    # If inject_fake cached a preview for this round, consume and use it so the
    # player sees the exact same question they were shown during the preview.
    case :ets.lookup(:truth_inject_preview, {room_id, round}) do
      [{{^room_id, ^round}, cached_q}] ->
        :ets.delete(:truth_inject_preview, {room_id, round})
        # Mark the question as used in history so it isn't repeated later.
        cat = Map.get(cached_q, :category, "general")
        mark_question_used(room_id, cat, cached_q.id)
        cached_q

      _ ->
        pools = truth_question_pools()

        category =
          cond do
            is_binary(forced_category) and forced_category != "" and Map.has_key?(pools, forced_category) ->
              forced_category

            true ->
              case get_truth_active_category(room_id) do
                nil ->
                  init_truth_active_category(room_id)
                  get_truth_active_category(room_id)

                cat ->
                  cat
              end
          end

        generate_truth_question_from_category(room_id, round, category, :sequential)
    end
  end

  defp generate_truth_question_from_category(room_id, round, category, pick_mode) do
    pools = truth_question_pools()
    cat = if Map.has_key?(pools, category), do: category, else: hd(Map.keys(pools) |> Enum.sort())
    questions = Map.fetch!(pools, cat)
    q_base = pick_truth_question(room_id, cat, round, questions, pick_mode)

    q =
      q_base
      |> Map.put(:category, cat)
      |> Map.put(:time_limit, 120)

    if pick_mode == :random do
      Map.put(q, :id, "#{q.id}-#{cat}-#{System.unique_integer([:positive])}")
    else
      q
    end
  end

  defp pick_truth_question(room_id, category, round, questions, pick_mode) do
    history_key = {room_id, category}

    used_ids =
      case :ets.lookup(:truth_question_history, history_key) do
        [{^history_key, ids}] when is_list(ids) -> ids
        _ -> []
      end

    used_set = MapSet.new(used_ids)
    available = Enum.reject(questions, fn q -> MapSet.member?(used_set, q.id) end)

    available =
      if available == [] do
        :ets.insert(:truth_question_history, {history_key, []})
        questions
      else
        available
      end

    selected =
      cond do
        pick_mode == :random ->
          Enum.at(available, :rand.uniform(length(available)) - 1)

        true ->
          Enum.at(available, rem(round - 1, length(available)))
      end

    next_used = Enum.take((used_ids ++ [selected.id]) |> Enum.uniq(), length(questions))
    :ets.insert(:truth_question_history, {history_key, next_used})
    ensure_question_min_options(selected, category)
  end

  # Mark a question as used in history without picking a new one.
  # Called when consuming a cached inject_fake preview.
  defp mark_question_used(room_id, category, question_id) do
    history_key = {room_id, category}
    pools = truth_question_pools()
    pool_size = pools |> Map.get(category, []) |> length() |> max(1)

    used_ids =
      case :ets.lookup(:truth_question_history, history_key) do
        [{^history_key, ids}] when is_list(ids) -> ids
        _ -> []
      end

    next_used = Enum.take((used_ids ++ [question_id]) |> Enum.uniq(), pool_size)
    :ets.insert(:truth_question_history, {history_key, next_used})
  end

  defp ensure_question_min_options(q, category) do
    cat = category || Map.get(q, :category) || "general"
    opts = Map.get(q, :options, [])

    if length(opts) >= @min_truth_options do
      q
    else
      existing_texts =
        opts
        |> Enum.map(&String.downcase(String.trim(&1.text)))
        |> MapSet.new()

      extras =
        category_distractor_texts(cat, q.text, @min_truth_options)
        |> Enum.reject(fn t -> MapSet.member?(existing_texts, String.downcase(t)) end)
        |> Enum.take(@min_truth_options - length(opts))

      used_ids = Enum.map(opts, & &1.id)

      new_opts =
        Enum.reduce(extras, {opts, used_ids}, fn text, {acc, ids} ->
          nid = next_option_id(ids)
          {[%{id: nid, text: text} | acc], ids ++ [nid]}
        end)
        |> elem(0)
        |> Enum.reverse()
        |> Enum.sort_by(& &1.id)

      %{q | options: new_opts}
    end
  end

  defp category_distractor_texts(cat, question_text, count) do
    base = category_base_distractors(cat)

    themed =
      case question_text do
        t when is_binary(t) and t != "" ->
          words =
            t
            |> String.replace(~r/[^\w\s]/u, "")
            |> String.split(~r/\s+/, trim: true)
            |> Enum.filter(&(String.length(&1) > 3))
            |> Enum.take(3)

          Enum.map(1..count, fn i ->
            hint = Enum.at(words, rem(i, max(length(words), 1))) || "liên quan"
            "Không chắc: #{hint} (biến thể #{i})"
          end)

        _ ->
          []
      end

    (base ++ themed) |> Enum.uniq() |> Enum.take(count)
  end

  defp category_base_distractors("general"),
    do: ["Không có đáp án nào", "Tất cả đáp án trên", "Không áp dụng", "Không rõ", "Tùy ngữ cảnh", "Không thể xác định", "Chỉ trên lý thuyết", "Chỉ trong thực tế", "Cả A và C"]

  defp category_base_distractors("science_lite"),
    do: ["Heli", "Neon", "Argon", "Krypton", "Xenon", "Radon", "Plasma", "Chân không", "Độ không tuyệt đối"]

  defp category_base_distractors("geography"),
    do: ["Dãy Andes", "Dãy Himalaya", "Sa mạc Sahara", "Sa mạc Gobi", "Bắc Băng Dương", "Địa Trung Hải", "Đường xích đạo", "Kinh tuyến gốc", "Chí tuyến Bắc"]

  defp category_base_distractors("history"),
    do: ["1914", "1918", "1939", "1941", "1969", "1776", "1066", "1492", "2001"]

  defp category_base_distractors("technology"),
    do: ["FTP", "SMTP", "DNS", "TCP", "UDP", "HTML", "CSS", "JSON", "XML"]

  defp category_base_distractors("food_culture"),
    do: ["Sushi", "Taco", "Cà ri", "Bánh mì Pháp", "Pizza", "Ramen", "Tapas", "Nướng BBQ", "Salad"]

  defp category_base_distractors("sports_lite"),
    do: ["Cricket", "Bóng bầu dục", "Golf", "Quyền Anh", "Bơi lội", "Đua xe đạp", "Trượt tuyết", "Bóng chuyền", "Bóng ném"]

  defp category_base_distractors("pop_culture"),
    do: ["Marvel", "DC", "Anime", "K-pop", "Nhạc kịch Broadway", "Netflix", "Podcast", "Meme", "Xu hướng viral"]

  defp category_base_distractors("social_stats"),
    do: ["Trung bình cộng", "Trung vị", "Yếu vị", "Sai lệch mẫu", "Nhóm đối chứng", "Tương quan", "Nhân quả", "Giá trị ngoại lai", "Khoảng tin cậy"]

  defp category_base_distractors("weird_facts"),
    do: ["Huyền thoại", "Tin đồn đô thị", "Mẹo dân gian", "Trò lừa", "Mê tín", "Niềm tin dân gian", "Tin đồn", "Câu view", "Đã bị bác bỏ"]

  defp category_base_distractors(_),
    do: category_base_distractors("general")

  defp truth_question_pools do
    VnParty.TruthQuestionBank.pools()
    |> ensure_min_questions_per_category(@min_questions_per_category)
    |> Enum.map(fn {cat, qs} -> {cat, Enum.map(qs, &ensure_question_min_options(&1, cat))} end)
    |> Enum.into(%{})
  end

  defp ensure_min_questions_per_category(pools, min_n) do
    Enum.into(pools, %{}, fn {cat, qs} ->
      missing = max(min_n - length(qs), 0)

      generated =
        Enum.map(1..missing, fn i ->
          n = length(qs) + i
          {prompt, choices} = generated_truth_prompt_and_choices(cat, n)

          letters = Enum.map(0..(@min_truth_options - 1), fn j -> <<?A + j>> end)

          options =
            Enum.zip(letters, choices ++ category_distractor_texts(cat, prompt, @min_truth_options))
            |> Enum.take(@min_truth_options)
            |> Enum.map(fn {id, text} -> %{id: id, text: text} end)

          %{
            id: "#{cat}_gen_#{n}",
            text: prompt,
            options: options,
            correct: "A"
          }
        end)

      {cat, Enum.map(qs ++ generated, &ensure_question_min_options(&1, cat))}
    end)
  end

  defp next_option_id(existing_ids) do
    letters = 0..(@min_truth_options + 5) |> Enum.map(fn i -> <<?A + i>> end)
    Enum.find(letters, fn l -> l not in existing_ids end) || "Z#{System.unique_integer([:positive])}"
  end

  defp generated_truth_prompt_and_choices(cat, _n) do
    case cat do
      "technology" ->
        {"Thuật ngữ nào liên quan trực tiếp đến máy tính?",
         ["Cơ sở dữ liệu", "Trình biên dịch", "Nhân hệ điều hành", "API", "Bộ nhớ đệm", "Bộ định tuyến", "Tường lửa", "Giao thức", "Thuật toán"]}

      "geography" ->
        {"Đâu là một quốc gia?",
         ["Peru", "Chile", "Ecuador", "Bolivia", "Paraguay", "Uruguay", "Colombia", "Venezuela", "Guyana"]}

      "history" ->
        {"Đâu là một thời kỳ lịch sử?",
         ["Phục Hưng", "Khai Sáng", "Công Nghiệp", "Đồ Đồng", "Đồ Sắt", "Trung Cổ", "Victoria", "Chiến Tranh Lạnh", "La Mã Cổ Đại"]}

      "sports_lite" ->
        {"Đâu là một môn thể thao Olympic?",
         ["Bắn cung", "Đấu kiếm", "Judo", "Chèo thuyền", "Nhảy cầu", "Boxing", "Đua xe đạp", "Bơi lội", "Điền kinh"]}

      "food_culture" ->
        {"Đâu là thực phẩm lên men?",
         ["Kimchi", "Dưa cải bắp", "Sữa chua", "Miso", "Tempeh", "Kefir", "Dưa muối", "Natto", "Kombucha"]}

      "pop_culture" ->
        {"Đâu là một thể loại phim?",
         ["Khoa học viễn tưởng", "Kinh dị", "Hài", "Chính kịch", "Lãng mạn", "Giật gân", "Tài liệu", "Hoạt hình", "Miền Tây"]}

      "science_lite" ->
        {"Đâu là hành tinh trong hệ mặt trời?",
         ["Sao Thủy", "Sao Kim", "Trái Đất", "Sao Hỏa", "Sao Mộc", "Sao Thổ", "Sao Thiên Vương", "Sao Hải Vương", "Sao Diêm Vương (lùn)"]}

      "social_stats" ->
        {"Đâu là mạng xã hội phổ biến?",
         ["Instagram", "Facebook", "TikTok", "YouTube", "LinkedIn", "Snapchat", "Twitter/X", "Reddit", "Pinterest"]}

      "weird_facts" ->
        {"Động vật nào có thể tái tạo chi bị mất?",
         ["Sao biển", "Kỳ nhông", "Giun dẹp", "Cua", "Đuôi thằn lằn", "Hải sâm", "Bọt biển", "Thủy tức", "Axolotl"]}

      "general" ->
        {"Đâu là một nguyên tố hóa học?",
         ["Oxy", "Hydro", "Nitơ", "Carbon", "Heli", "Neon", "Sắt", "Đồng", "Bạc"]}

      _ ->
        {"Đâu là đơn vị đo lường?",
         ["Kilogram", "Mét", "Giây", "Ampe", "Kelvin", "Mole", "Candela", "Lít", "Hecta"]}
    end
  end

  defp apply_final_collapse_effects(question) do
    correct_ids = if is_list(question.correct), do: question.correct, else: [question.correct]

    incorrect = Enum.filter(question.options, fn o -> o.id not in correct_ids end)
    removed = if incorrect == [], do: nil, else: Enum.at(incorrect, :rand.uniform(length(incorrect)) - 1)
    options = if removed, do: Enum.reject(question.options, fn o -> o.id == removed.id end), else: question.options

    primary = List.first(correct_ids)

    alt = Enum.find(options, fn o -> o.id not in correct_ids end)

    multi_correct =
      if length(options) >= 2 and alt do
        Enum.uniq([primary, alt.id])
      else
        correct_ids
      end

    # Keep the same pacing on the final round (no surprise fast timer).
    %{question | options: Enum.sort_by(options, & &1.id), correct: multi_correct}
  end

  defp generate_mock_question(round) do
    # For now, return mock Vietnamese trivia questions with option IDs A-D
    questions = [
      %{
        id: "q1",
        text: "Tết Nguyên Đán là ngày lễ quan trọng nhất trong năm của người Việt. Tết thường diễn ra vào tháng nào?",
        options: [
          %{id: "A", text: "Tháng 12 dương lịch"},
          %{id: "B", text: "Tháng 1 hoặc tháng 2 dương lịch"},
          %{id: "C", text: "Tháng 3 dương lịch"},
          %{id: "D", text: "Tháng 4 dương lịch"}
        ],
        correct: "B",
        time_limit: 15
      },
      %{
        id: "q2",
        text: "Món ăn nào sau đây là đặc sản nổi tiếng của Việt Nam?",
        options: [
          %{id: "A", text: "Phở"},
          %{id: "B", text: "Sushi"},
          %{id: "C", text: "Pizza"},
          %{id: "D", text: "Burger"}
        ],
        correct: "A",
        time_limit: 15
      },
      %{
        id: "q3",
        text: "Thủ đô hiện tại của Việt Nam là thành phố nào?",
        options: [
          %{id: "A", text: "TP. Hồ Chí Minh"},
          %{id: "B", text: "Hà Nội"},
          %{id: "C", text: "Đà Nẵng"},
          %{id: "D", text: "Huế"}
        ],
        correct: "B",
        time_limit: 15
      },
      %{
        id: "q4",
        text: "Hồ Hoàn Kiếm nằm ở thành phố nào?",
        options: [
          %{id: "A", text: "Hà Nội"},
          %{id: "B", text: "TP. Hồ Chí Minh"},
          %{id: "C", text: "Đà Nẵng"},
          %{id: "D", text: "Cần Thơ"}
        ],
        correct: "A",
        time_limit: 15
      },
      %{
        id: "q5",
        text: "Năm nào đánh dấu sự kiện Việt Nam thống nhất đất nước?",
        options: [
          %{id: "A", text: "1945"},
          %{id: "B", text: "1954"},
          %{id: "C", text: "1975"},
          %{id: "D", text: "1986"}
        ],
        correct: "C",
        time_limit: 15
      }
    ]

    index = rem(round - 1, length(questions))
    Enum.at(questions, index)
  end

  defp save_committed_answer(commit, db_attrs, room_id, round) do
    if Game.cache_enabled?() do
      updated = struct(commit, db_attrs)
      list =
        case :ets.lookup(:answer_commits_cache, {room_id, round}) do
          [{_, existing}] -> existing
          _ -> []
        end
      list = Enum.map(list, fn c -> if c.id == updated.id, do: updated, else: c end)
      :ets.insert(:answer_commits_cache, {{room_id, round}, list})
      :ets.insert(:answer_commits_cache, {updated.id, updated})
      {:ok, updated}
    else
      commit
      |> Ecto.Changeset.change(db_attrs)
      |> Repo.update()
    end
  end

  defp save_scored_commit(commit, is_correct, points, room_id, round) do
    if Game.cache_enabled?() do
      updated = %{commit | is_correct: is_correct, points_awarded: points}
      list =
        case :ets.lookup(:answer_commits_cache, {room_id, round}) do
          [{_, existing}] -> existing
          _ -> []
        end
      list = Enum.map(list, fn c -> if c.id == updated.id, do: updated, else: c end)
      :ets.insert(:answer_commits_cache, {{room_id, round}, list})
      :ets.insert(:answer_commits_cache, {updated.id, updated})
      {:ok, updated}
    else
      commit
      |> AnswerCommit.score_changeset(is_correct, points)
      |> Repo.update()
    end
  end
end
