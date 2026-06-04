defmodule VnPartyWeb.GameChannel do
  use VnPartyWeb, :channel
  alias VnParty.Game
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
        # Assign room and player info to socket
        # Use room.code from DB for consistent broadcasting (handles case mismatch)
        socket =
          socket
          |> assign(:room_id, room.id)
          |> assign(:room_code, room.code)
          |> assign(:player_id, player_id)
          |> assign(:nickname, nickname)

        Presence.mark_connected(player_id)

        # Subscribe to room's internal topic so we can receive timer events
        # (ensures timer fires even if the player who started the game disconnects)
        PubSub.subscribe(VnParty.PubSub, "room:#{room.id}:internal")

        # Schedule broadcast to happen after join completes
        send(self(), :after_join)

        # If game is in progress, send current question options only (no text)
        game_state = get_game_state(room)
        response =
          if room.state == "round_start" and room.current_round > 0 do
            # IMPORTANT:
            # - Classic mode: we can provide a lightweight current_question on join.
            # - Truth Collapse: do NOT inject a classic mock question here (it breaks timers/UX).
            if Game.room_mode(room) == "truth_collapse" do
              game_state
            else
              question = generate_mock_question(room.current_round)
              IO.puts("📤 Sending current question options to new joiner for round #{room.current_round}")
              player_question = %{
                id: question.id,
                options: ["A", "B", "C", "D"],
                time_limit: question.time_limit
              }
              Map.put(game_state, :current_question, player_question)
            end
          else
            game_state
          end

        # Send current game state to the joining player (with question if game in progress)
        {:ok, response, socket}
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

        commit
        |> Ecto.Changeset.change(db_attrs)
        |> Repo.update()

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
          # Use ETS to atomically check and mark that auto-reveal is scheduled
          # This prevents multiple processes from scheduling the same auto-reveal
          auto_reveal_key = {:auto_reveal_scheduled, room_id, room.current_round}
          case :ets.insert_new(:round_scored, {auto_reveal_key, true}) do
            true ->
              IO.puts("✅ All connected players committed! Auto-revealing in 2 seconds...")
              # All connected players committed, trigger auto-reveal after 2 seconds
              # This gives time for the UI to update before showing results
              Process.send_after(self(), {:auto_reveal, room.current_round, question_id}, 2000)
            false ->
              IO.puts("⏳ Auto-reveal already scheduled by another process")
          end
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

      mode =
        try do
          room_id && Game.get_room!(room_id) |> Game.room_mode()
        rescue
          _ -> nil
        end

      round =
        try do
          if room_id, do: Game.get_room!(room_id).current_round, else: nil
        rescue
          _ -> nil
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

  @impl true
  def handle_in("heartbeat", _payload, socket) do
    Presence.mark_connected(socket.assigns.player_id)
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
    {:stop, :normal, socket}
  end

  @impl true
  def handle_in("submit_prediction", payload, socket) do
    %{"option_id" => option_id} = payload
    room = Game.get_room!(socket.assigns.room_id)
    if Game.room_mode(room) != "truth_collapse" do
      {:reply, {:error, %{reason: "Predictions are only available in Truth Collapse"}}, socket}
    else
      maybe_record_latency(socket, "submit_prediction", payload, %{option_id: option_id})
      key = {socket.assigns.room_id, room.current_round, socket.assigns.player_id}
      :ets.insert(:truth_predictions, {key, option_id})

      counts = build_prediction_counts(socket.assigns.room_id, room.current_round)
      counts_payload = %{round: room.current_round, counts: counts}
      Endpoint.broadcast("display:#{socket.assigns.room_code}", "display:option_counts_updated", counts_payload)
      broadcast!(socket, "option_counts_updated", counts_payload)

      {:reply, {:ok, %{saved: true}}, socket}
    end
  end

  @impl true
  def handle_in("use_distortion", %{"action" => action} = payload, socket) do
    room = Game.get_room!(socket.assigns.room_id)
    if Game.room_mode(room) != "truth_collapse" do
      {:reply, {:error, %{reason: "Distortions are only available in Truth Collapse"}}, socket}
    else
      maybe_record_latency(socket, "use_distortion", payload, %{action: action})
      if action == "inject_fake_option" do
        {:reply, {:error, %{reason: "Use fake-option lock flow first"}}, socket}
      else
      player_id = socket.assigns.player_id
      cost = distortion_cost(action)
      stats = get_truth_stats(player_id)

      cond do
        stats.charges < cost ->
          {:reply, {:error, %{reason: "Not enough distortion power"}}, socket}

        not DistortionRules.can_use?(room.id, player_id, action) ->
          {:reply, {:error, %{reason: DistortionRules.denial_reason(action)}}, socket}

        true ->
        case validate_distortion_payload(action, payload, room, player_id) do
          {:error, reason} ->
            {:reply, {:error, %{reason: reason}}, socket}

          {:ok, cleaned_payload} ->
            DistortionRules.record_use!(room.id, player_id, action)
            update_truth_stats(player_id, fn s -> %{s | charges: max(0, s.charges - cost), di: s.di + cost * 10} end)
            :ets.insert(:truth_distortions, {socket.assigns.room_id, room.current_round, player_id, action, cleaned_payload})

            Game.create_event(room.id, "distortion_used", %{
              action: action,
              round: room.current_round,
              payload: cleaned_payload
            }, player_id)

            log_payload = %{
              round: room.current_round,
              player_id: player_id,
              nickname: socket.assigns.nickname,
              action: action,
              payload: cleaned_payload,
              remaining_charges: get_truth_stats(player_id).charges
            }

            broadcast_to_both(socket, "distortion_used", log_payload, "display:distortion_used", log_payload)

            # Push updated truth stats snapshot to players so they can render charges/UI.
            players_now = Game.list_players(socket.assigns.room_id)
            stats_public =
              Enum.map(players_now, fn p ->
                s = get_truth_stats(p.id)
                %{player_id: p.id, tp: s.tp, di: s.di, ps: s.ps, charges: s.charges}
              end)
            broadcast!(socket, "truth_stats_updated", %{stats: stats_public})

            {:reply, {:ok, %{used: true, remaining_charges: get_truth_stats(player_id).charges}}, socket}
        end
      end
      end
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

      true ->
        lock_key = {room.id, room.current_round, player_id}
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
            base_q = generate_question_for_mode(room, next_round)
            base_q = ensure_truth_question_option_capacity(base_q, count_connected(room.id) + 1)
            next_q = resize_truth_options_for_players(base_q, count_connected(room.id))
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
    room = Game.get_room!(socket.assigns.room_id)
    player_id = socket.assigns.player_id
    lock_key = {room.id, room.current_round, player_id}
    maybe_record_latency(socket, "set_fake_option_text", payload, %{})

    if Game.room_mode(room) != "truth_collapse" do
      {:reply, {:error, %{reason: "Distortions are only available in Truth Collapse"}}, socket}
    else
      case :ets.lookup(:truth_fake_locks, lock_key) do
        [] ->
          {:reply, {:error, %{reason: "You must lock this power first"}}, socket}

        _ ->
          case validate_distortion_payload("inject_fake_option", %{"fake_text" => fake_text}, room, player_id) do
            {:error, reason} ->
              {:reply, {:error, %{reason: reason}}, socket}

            {:ok, cleaned_payload} ->
              DistortionRules.record_use!(room.id, player_id, "inject_fake_option")
              :ets.insert(:truth_distortions, {room.id, room.current_round, player_id, "inject_fake_option", cleaned_payload})
              :ets.delete(:truth_fake_locks, lock_key)

              Game.create_event(room.id, "distortion_used", %{
                action: "inject_fake_option",
                round: room.current_round,
                payload: cleaned_payload
              }, player_id)

              log_payload = %{
                round: room.current_round,
                player_id: player_id,
                nickname: socket.assigns.nickname,
                action: "inject_fake_option",
                payload: cleaned_payload,
                remaining_charges: get_truth_stats(player_id).charges
              }

              broadcast_to_both(socket, "distortion_used", log_payload, "display:distortion_used", log_payload)
              {:reply, {:ok, %{used: true}}, socket}
          end
      end
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
      :ets.insert(:truth_results_ack, {{room_id, round, player_id}, true})

      players = Game.list_players(room_id)
      connected = Enum.filter(players, & &1.connected)

      acked_ids =
        Enum.filter(connected, fn p ->
          case :ets.lookup(:truth_results_ack, {room_id, round, p.id}) do
            [_] -> true
            [] -> false
          end
        end)
        |> Enum.map(& &1.id)

      progress = %{
        round: round,
        acked_count: length(acked_ids),
        total: length(connected),
        acked_player_ids: acked_ids
      }

      broadcast_to_both(socket, "truth_results_progress", progress, "display:truth_results_progress", progress)

      if length(connected) > 0 and length(acked_ids) >= length(connected) do
        send(self(), {:auto_advance_round, room_id, round})
      end

      {:reply, {:ok, %{received: true}}, socket}
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

    total_players = rematch_snapshot_total(room_id)
    vote_count = MapSet.size(updated_votes)

    IO.puts("🔄 Rematch vote from player #{player_id}: #{vote_count}/#{total_players} (connected players only)")
    IO.puts("   All voters: #{inspect(MapSet.to_list(updated_votes))}")
    IO.puts("   Snapshot total players: #{total_players}")

    # Broadcast updated vote count to ALL players immediately
    vote_payload = %{
      vote_count: vote_count,
      total_players: total_players,
      voters: MapSet.to_list(updated_votes)
    }
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

    total_players = rematch_snapshot_total(room_id)
    declined_count = MapSet.size(updated_declined)

    IO.puts("❌ Rematch declined: #{declined_count}/#{total_players}")

    votes = case :ets.lookup(:rematch_votes, room_id) do
      [] -> MapSet.new()
      [{^room_id, v}] -> v
    end
    vote_count = MapSet.size(votes)

    vote_payload = %{
      vote_count: vote_count,
      total_players: total_players,
      voters: MapSet.to_list(votes)
    }
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
    # Get updated player list
    players = Game.list_players(socket.assigns.room_id)

    # Broadcast that player joined: same info to both channels
    player_joined_payload = %{
      player_id: socket.assigns.player_id,
      nickname: socket.assigns.nickname,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      players: format_players(players)
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
      stored = case :ets.lookup(:truth_round_data, {room_id, round}) do
        [{{^room_id, ^round}, data}] -> data
        _ -> nil
      end

      base_question = generate_question_for_mode(room, round)
      {question, effects} =
        if stored do
          conn = count_connected(room_id)
          q = resize_truth_options_for_players(stored.question, conn)
          :ets.insert(:truth_round_data, {{room_id, round}, %{question: q, effects: stored.effects}})
          {q, stored.effects}
        else
          {q0, eff} = apply_distortions_for_round(room_id, round, base_question)
          q = resize_truth_options_for_players(q0, count_connected(room_id))
          {q, eff}
        end

      :ets.insert(:truth_room_phase, {room_id, %{round: round, phase: "answering"}})
      :ets.insert(:truth_answering_mono, {{room_id, round}, System.monotonic_time(:millisecond)})

      merged = merge_realities_used?(room_id, round)

      player_question = %{
        id: question.id,
        options: Enum.map(question.options, & &1.id),
        time_limit: question.time_limit,
        # Treat force_blind as "shuffle answers" on player devices (host still sees stable layout)
        shuffle_targets: MapSet.to_list(effects.blind_targets),
        remove_targets: Map.get(effects, :remove_targets, %{})
      }

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

          round_started_payload =
            if Game.room_mode(updated_room) == "truth_collapse" do
              {pre_q, _} = prepare_truth_round_question(updated_room, updated_room.current_round)
              cat = get_truth_active_category(updated_room.id)
              opt_ids = Enum.map(pre_q.options, & &1.id)

              sync =
                if is_binary(cat) do
                  %{
                    category: cat,
                    category_label: truth_category_label(cat),
                    option_ids: opt_ids
                  }
                else
                  %{option_ids: opt_ids}
                end

              Map.merge(round_started_payload, sync)
            else
              round_started_payload
            end

          broadcast_to_both(socket, "round_started", round_started_payload, "display:round_started", round_started_payload)

          if Game.room_mode(updated_room) == "truth_collapse" do
            start_truth_round_flow(socket, updated_room, updated_room.current_round)
          else
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

      # Set up rematch timeout (30 seconds)
      Process.send_after(self(), {:rematch_timeout, room_id}, 30_000)
    end

      {:noreply, socket}
    end
  end

  @impl true
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

        approved_payload = %{message: "#{vote_count} players confirmed rematch.", voters: MapSet.to_list(votes)}
        broadcast_to_both(socket, "rematch_approved", approved_payload, "display:rematch_approved", approved_payload)

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

      approved_payload = %{message: "#{vote_count} players confirmed rematch.", voters: MapSet.to_list(votes)}
      broadcast_to_both(socket, "rematch_approved", approved_payload, "display:rematch_approved", approved_payload)
    else
      clear_rematch_state(room_id)

      cancelled_payload = %{message: "Rematch was not approved in time.", kick_to_home: true}
      broadcast_to_both(socket, "rematch_cancelled", cancelled_payload, "display:rematch_cancelled", cancelled_payload)
    end

    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:room_id] do
      PubSub.unsubscribe(VnParty.PubSub, "room:#{socket.assigns.room_id}:internal")
    end

    if socket.assigns[:player_id] and socket.assigns[:room_code] and not socket.assigns[:left_voluntarily] do
      room_id = socket.assigns.room_id
      player_id = socket.assigns.player_id
      room_code = socket.assigns.room_code
      room = Game.get_room!(room_id)

      if room.state not in ["lobby", "game_end"] do
        Game.mark_skip_next_round(room_id, player_id)
      end

      Game.player_left(player_id, room_code)
    end

    maybe_register_rematch_disconnect_vote(socket)

    :ok
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

  defp start_truth_round_flow(socket, room, round) do
    # "Preparing/discussion" phase duration
    discussion_seconds = 15

    # Ensure stale dedupe flags from previous runs cannot block answering transition.
    :ets.delete(:round_scored, {{:truth_q_started, room.id, round}, true})
    :ets.delete(:round_scored, {:truth_q_started, room.id, round})

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
            commit
            |> AnswerCommit.score_changeset(is_correct, points)
            |> Repo.update()

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
        Process.send_after(self(), {:auto_advance_round, room_id, room.current_round}, 5000)
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

            commit
            |> AnswerCommit.score_changeset(is_correct, points)
            |> Repo.update()

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
        Process.send_after(self(), {:auto_advance_round, room_id, room.current_round}, 5000)
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
            commit
            |> AnswerCommit.score_changeset(is_correct, points)
            |> Repo.update()

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
        Process.send_after(self(), {:auto_advance_round, room_id, room.current_round}, 5000)
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

            commit
            |> AnswerCommit.score_changeset(is_correct, points)
            |> Repo.update()

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
        Process.send_after(self(), {:auto_advance_round, room_id, room.current_round}, 5000)
      end

      {:noreply, socket}
    end
  end

  defp reset_room_for_rematch(room_id) do
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
    :ets.match_delete(:truth_question_history, {{room_id, :_}, :_})
    :ets.match_delete(:truth_fake_locks, {{room_id, :_, :_}, :_})

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

  # Truth Collapse: option count follows connected players (capped by available options in the pool).
  defp resize_truth_options_for_players(q, connected_n) when connected_n < 0, do: q

  defp resize_truth_options_for_players(%{options: []} = q, _), do: q
  defp resize_truth_options_for_players(%{injected_option_ids: ids} = q, _) when is_list(ids) and ids != [], do: q

  defp resize_truth_options_for_players(%{options: options} = q, connected_n) do
    want = max(min(connected_n + 1, length(options)), 2)
    correct_ids = if is_list(q.correct), do: q.correct, else: [q.correct]
    kept_correct = Enum.filter(options, fn o -> o.id in correct_ids end)
    wrongs = Enum.reject(options, fn o -> o.id in correct_ids end)
    need_wrong = max(0, want - length(kept_correct))
    keep_ids =
      (Enum.map(kept_correct, & &1.id) ++ Enum.map(Enum.take(wrongs, need_wrong), & &1.id))
      |> MapSet.new()

    ordered = Enum.filter(options, fn o -> MapSet.member?(keep_ids, o.id) end)
    %{q | options: ordered}
  end

  defp ensure_truth_question_option_capacity(%{options: options} = q, want) do
    want = max(want, 4)

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
          current_question: %{
            id: q2.id,
            options: Enum.map(q2.options, & &1.id),
            time_limit: q2.time_limit,
            shuffle_targets: MapSet.to_list(eff.blind_targets),
            remove_targets: Map.get(eff, :remove_targets, %{})
          }
        })

      _ ->
        base
    end
  end

  defp resume_truth_results(room_id, round, base) do
    case :ets.lookup(:truth_last_results, {room_id, round}) do
      [{{^room_id, ^round}, snap}] ->
        Map.merge(base, snap)

      [] ->
        base
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
    prior_round = round - 1

    distortions_raw =
      :ets.lookup(:truth_distortions, room_id)
      |> Enum.flat_map(fn
        {^room_id, ^prior_round, pid, action, payload} ->
          [%{round: prior_round, player_id: pid, action: action, payload: payload, di: get_truth_stats(pid).di}]

        _ ->
          []
      end)

    players = Game.list_players(room_id)
    connected_players = Enum.filter(players, & &1.connected)
    player_ids = Enum.map(connected_players, & &1.id)

    ordered =
      distortions_raw
      |> Enum.sort_by(fn d -> {-d.di, :rand.uniform(10_000)} end)

    initial_category = Map.get(question, :category)

    acc_init = %{
      q: question,
      timeline: if(initial_category, do: [initial_category], else: []),
      log: [],
      remove_count: 0,
      force_blind_entries: [],
      remove_entries: [],
      fake_entries: []
    }

    acc =
      Enum.reduce(ordered, acc_init, fn d, a ->
        case d.action do
          "swap_category" ->
            requested = Map.get(d.payload, "category", Map.get(d.payload, :category))
            cat = pick_swap_category(a.q, requested)
            new_q = generate_truth_question_from_category(room_id, round, cat, :random)

            entry = %{
              player_id: d.player_id,
              action: d.action,
              category: cat,
              category_label: truth_category_label(cat)
            }

            %{a | q: new_q, timeline: a.timeline ++ [cat], log: a.log ++ [entry]}

          "remove_option" ->
            target = Map.get(d.payload, "target_player_id", Map.get(d.payload, :target_player_id))
            entry = %{player_id: d.player_id, action: d.action, target_player_id: target}
            %{a | remove_count: a.remove_count + 1, remove_entries: a.remove_entries ++ [entry], log: a.log ++ [entry]}

          "force_blind" ->
            target = Map.get(d.payload, "target_player_id", Map.get(d.payload, :target_player_id))

            entry = %{
              player_id: d.player_id,
              action: d.action,
              target_player_id: target
            }

            %{a | force_blind_entries: a.force_blind_entries ++ [entry], log: a.log ++ [entry]}

          "inject_fake_option" ->
            fake_text = Map.get(d.payload, "fake_text", Map.get(d.payload, :fake_text))
            entry = %{player_id: d.player_id, action: d.action, fake_text: fake_text}
            %{a | fake_entries: a.fake_entries ++ [entry], log: a.log ++ [entry]}

          "merge_realities" ->
            %{a | log: a.log ++ [%{player_id: d.player_id, action: d.action}]}

          _ ->
            %{a | log: a.log ++ [%{player_id: d.player_id, action: d.action}]}
        end
      end)

    blind_targets =
      if length(acc.force_blind_entries) >= 2 do
        MapSet.new(player_ids)
      else
        Enum.reduce(acc.force_blind_entries, MapSet.new(), fn %{player_id: source_id, target_player_id: t}, ms ->
          cond do
            t == "__all_others__" ->
              Enum.reduce(player_ids, ms, fn pid, acc_ms ->
                if pid != source_id, do: MapSet.put(acc_ms, pid), else: acc_ms
              end)

            is_binary(t) and t != "" ->
              MapSet.put(ms, t)

            true ->
              ms
          end
        end)
      end

    q1 = acc.q

    incorrect =
      Enum.filter(q1.options, fn o ->
        !(if is_list(q1.correct), do: o.id in q1.correct, else: o.id == q1.correct)
      end)

    min_options = min(length(q1.options), max(length(connected_players) + 1, 2))
    max_removable = max(length(incorrect) - max(0, min_options - 1), 0)
    remove_n = min(acc.remove_count, max_removable)

    removed_ids =
      incorrect
      |> Enum.take(remove_n)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    q2 = %{q1 | options: Enum.reject(q1.options, fn o -> MapSet.member?(removed_ids, o.id) end)}

    incorrect_ids_q2 =
      Enum.filter(q2.options, fn o ->
        !(if is_list(q2.correct), do: o.id in q2.correct, else: o.id == q2.correct)
      end)
      |> Enum.map(& &1.id)

    remove_targets =
      Enum.reduce(acc.remove_entries, %{}, fn %{target_player_id: t}, m ->
        if is_binary(t) and t != "" and t in player_ids and incorrect_ids_q2 != [] do
          current = Map.get(m, t, MapSet.new())
          available = Enum.reject(incorrect_ids_q2, &MapSet.member?(current, &1))

          next_set =
            case available do
              [] ->
                current

              _ ->
                pick = Enum.at(available, :rand.uniform(length(available)) - 1)
                MapSet.put(current, pick)
            end

          Map.put(m, t, next_set)
        else
          m
        end
      end)

    {q3, fake_entries_applied, injected_ids} =
      Enum.reduce(acc.fake_entries, {q2, [], MapSet.new()}, fn e, {q_acc, applied, used_ids} ->
        wrongs =
          Enum.filter(q_acc.options, fn o ->
            !(if is_list(q_acc.correct), do: o.id in q_acc.correct, else: o.id == q_acc.correct)
          end)
          |> Enum.reject(fn o -> MapSet.member?(used_ids, o.id) end)

        case wrongs do
          [] ->
            {q_acc, applied, used_ids}

          _ ->
            victim = Enum.at(wrongs, :rand.uniform(length(wrongs)) - 1)
            opts = Enum.map(q_acc.options, fn o -> if o.id == victim.id, do: %{o | text: e.fake_text}, else: o end)
            { %{q_acc | options: opts}, applied ++ [Map.put(e, :option_id, victim.id)], MapSet.put(used_ids, victim.id)}
        end
      end)

    injected_ids = MapSet.to_list(injected_ids)
    q3 = if injected_ids == [], do: q3, else: Map.put(q3, :injected_option_ids, injected_ids)

    effects = %{
      blind_targets: blind_targets,
      log: acc.log,
      category_timeline: acc.timeline,
      remove_count: acc.remove_count,
      force_blind_count: length(acc.force_blind_entries),
      remove_targets: Enum.into(remove_targets, %{}, fn {k, ms} -> {k, MapSet.to_list(ms)} end),
      fake_entries: fake_entries_applied,
      injected_option_ids: injected_ids
    }

    {q3, effects}
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

  defp truth_category_label("general"), do: "General"
  defp truth_category_label("weird_facts"), do: "Weird Facts"
  defp truth_category_label("social_stats"), do: "Social & Stats"
  defp truth_category_label("science_lite"), do: "Science (Lite)"
  defp truth_category_label("pop_culture"), do: "Pop Culture"
  defp truth_category_label("history"), do: "History"
  defp truth_category_label("geography"), do: "Geography"
  defp truth_category_label("food_culture"), do: "Food & Culture"
  defp truth_category_label("sports_lite"), do: "Sports (Lite)"
  defp truth_category_label("technology"), do: "Technology"
  defp truth_category_label(other) when is_binary(other), do: String.replace(other, "_", " ") |> String.capitalize()
  defp truth_category_label(_), do: "Unknown"

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
    connected_ids = room.id |> Game.list_players() |> Enum.filter(& &1.connected) |> Enum.map(& &1.id)

    cond do
      not is_binary(target) or target == "" ->
        {:error, "Please select a target player"}

      target not in connected_ids ->
        {:error, "Target player is not connected"}

      true ->
        {:ok, %{"target_player_id" => target}}
    end
  end

  defp validate_distortion_payload("inject_fake_option", payload, _room, _player_id) do
    raw = Map.get(payload, "fake_text", Map.get(payload, :fake_text, ""))
    txt = sanitize_fake_text(raw)

    cond do
      txt == "" -> {:error, "Please enter a fake answer"}
      String.length(txt) < 3 -> {:error, "Fake answer is too short"}
      String.length(txt) > 60 -> {:error, "Fake answer is too long (max 60 chars)"}
      contains_prohibited_text?(txt) -> {:error, "That text is not allowed by room safety filter"}
      true -> {:ok, %{"fake_text" => txt}}
    end
  end

  defp validate_distortion_payload("force_blind", payload, _room, _player_id) do
    target = Map.get(payload, "target_player_id", Map.get(payload, :target_player_id))
    if is_binary(target) and target != "" do
      {:ok, %{"target_player_id" => target}}
    else
      {:ok, %{"target_player_id" => "__all_others__"}}
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
        %{player_id: p.id, tp: s.tp, di: s.di, ps: s.ps, charges: s.charges}
      end)

    player_payload = %{round: round, mode: "truth_collapse", stats: stats_public}

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

    # Immediately sync "ready" counter so all clients show the same baseline.
    initial_progress = %{round: round, acked_count: 0, total: length(connected_players), acked_player_ids: []}
    broadcast_to_both(socket, "truth_results_progress", initial_progress, "display:truth_results_progress", initial_progress)

    # Give players time to think/use distortion powers before next round
    Process.send_after(self(), {:auto_advance_round, room_id, round}, 60_000)
    {:noreply, socket}
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

  # forced_category: internal use (e.g. tests); otherwise use persisted room category from ETS
  defp generate_truth_question(room, round, forced_category) do
    pools = truth_question_pools()
    room_id = room.id

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

    selected =
      cond do
        available != [] and pick_mode == :random ->
          Enum.at(available, :rand.uniform(length(available)) - 1)

        available != [] ->
          Enum.at(available, rem(round - 1, length(available)))

        pick_mode == :random ->
          Enum.at(questions, :rand.uniform(length(questions)) - 1)

        true ->
          Enum.at(questions, rem(round - 1, length(questions)))
      end

    next_used = Enum.take((used_ids ++ [selected.id]) |> Enum.uniq(), length(questions))
    :ets.insert(:truth_question_history, {history_key, next_used})
    selected
  end

  defp truth_question_pools do
    %{
      "general" => [
        %{id: "tg1", text: "Which country consumes the most coffee per capita?", options: [%{id: "A", text: "Finland"}, %{id: "B", text: "USA"}, %{id: "C", text: "Brazil"}, %{id: "D", text: "Japan"}], correct: "A"},
        %{id: "tg2", text: "How many hearts does an octopus have?", options: [%{id: "A", text: "1"}, %{id: "B", text: "2"}, %{id: "C", text: "3"}, %{id: "D", text: "4"}], correct: "C"},
        %{id: "tg3", text: "What is the smallest prime number?", options: [%{id: "A", text: "0"}, %{id: "B", text: "1"}, %{id: "C", text: "2"}, %{id: "D", text: "3"}], correct: "C"},
        %{id: "tg4", text: "Which planet is known as the Red Planet?", options: [%{id: "A", text: "Venus"}, %{id: "B", text: "Mars"}, %{id: "C", text: "Jupiter"}, %{id: "D", text: "Saturn"}], correct: "B"}
      ],
      "weird_facts" => [
        %{id: "tw1", text: "Roughly what percentage of people sleep with socks on?", options: [%{id: "A", text: "10%"}, %{id: "B", text: "20%"}, %{id: "C", text: "30%"}, %{id: "D", text: "50%"}], correct: "C"},
        %{id: "tw2", text: "Honey never spoils because it is highly acidic and low in moisture.", options: [%{id: "A", text: "Myth"}, %{id: "B", text: "True"}, %{id: "C", text: "Only in cold climates"}, %{id: "D", text: "Only pasteurized honey"}], correct: "B"},
        %{id: "tw3", text: "A group of flamingos is called a …", options: [%{id: "A", text: "Parliament"}, %{id: "B", text: "Flamboyance"}, %{id: "C", text: "Convocation"}, %{id: "D", text: "Huddle"}], correct: "B"}
      ],
      "social_stats" => [
        %{id: "ts1", text: "Most used social app globally by breadth of users?", options: [%{id: "A", text: "TikTok"}, %{id: "B", text: "Instagram"}, %{id: "C", text: "YouTube"}, %{id: "D", text: "Facebook"}], correct: "D"},
        %{id: "ts2", text: "Which age group reports the most daily screen time on average (typical surveys)?", options: [%{id: "A", text: "13–17"}, %{id: "B", text: "18–24"}, %{id: "C", text: "35–44"}, %{id: "D", text: "65+"}], correct: "B"},
        %{id: "ts3", text: "What is the approximate world literacy rate for adults?", options: [%{id: "A", text: "55%"}, %{id: "B", text: "70%"}, %{id: "C", text: "86%"}, %{id: "D", text: "95%"}], correct: "C"}
      ],
      "science_lite" => [
        %{id: "tc1", text: "What gas do plants primarily absorb for photosynthesis?", options: [%{id: "A", text: "Oxygen"}, %{id: "B", text: "Nitrogen"}, %{id: "C", text: "Carbon Dioxide"}, %{id: "D", text: "Helium"}], correct: "C"},
        %{id: "tc2", text: "Speed of light in vacuum is approximately?", options: [%{id: "A", text: "300 km/s"}, %{id: "B", text: "3,000 km/s"}, %{id: "C", text: "300,000 km/s"}, %{id: "D", text: "3 million km/s"}], correct: "C"},
        %{id: "tc3", text: "Water boils at 100°C at standard sea-level pressure.", options: [%{id: "A", text: "False"}, %{id: "B", text: "True"}, %{id: "C", text: "Only for salt water"}, %{id: "D", text: "Only above sea level"}], correct: "B"}
      ],
      "pop_culture" => [
        %{id: "tp1", text: "Which franchise features 'Jedi'?", options: [%{id: "A", text: "Star Wars"}, %{id: "B", text: "Star Trek"}, %{id: "C", text: "Dune"}, %{id: "D", text: "Avatar"}], correct: "A"},
        %{id: "tp2", text: "Who wrote the novel '1984'?", options: [%{id: "A", text: "Huxley"}, %{id: "B", text: "Orwell"}, %{id: "C", text: "Bradbury"}, %{id: "D", text: "Atwood"}], correct: "B"},
        %{id: "tp3", text: "Pac-Man is a character from which era of gaming?", options: [%{id: "A", text: "1970s arcade"}, %{id: "B", text: "1990s PC"}, %{id: "C", text: "2000s mobile"}, %{id: "D", text: "2010s VR"}], correct: "A"}
      ],
      "history" => [
        %{id: "th1", text: "World War II ended in Europe in which year?", options: [%{id: "A", text: "1943"}, %{id: "B", text: "1944"}, %{id: "C", text: "1945"}, %{id: "D", text: "1946"}], correct: "C"},
        %{id: "th2", text: "The Berlin Wall fell in which year?", options: [%{id: "A", text: "1987"}, %{id: "B", text: "1989"}, %{id: "C", text: "1991"}, %{id: "D", text: "1993"}], correct: "B"},
        %{id: "th3", text: "Ancient Olympic Games originated in?", options: [%{id: "A", text: "Rome"}, %{id: "B", text: "Greece"}, %{id: "C", text: "Egypt"}, %{id: "D", text: "Persia"}], correct: "B"}
      ],
      "geography" => [
        %{id: "tgeo1", text: "What is the longest river in the world (common geographic claim)?", options: [%{id: "A", text: "Amazon"}, %{id: "B", text: "Nile"}, %{id: "C", text: "Yangtze"}, %{id: "D", text: "Mississippi"}], correct: "B"},
        %{id: "tgeo2", text: "Mount Everest lies on the border of Nepal and which country?", options: [%{id: "A", text: "India"}, %{id: "B", text: "China"}, %{id: "C", text: "Bhutan"}, %{id: "D", text: "Pakistan"}], correct: "B"},
        %{id: "tgeo3", text: "Which is the smallest continent?", options: [%{id: "A", text: "Europe"}, %{id: "B", text: "Australia"}, %{id: "C", text: "Antarctica"}, %{id: "D", text: "South America"}], correct: "B"}
      ],
      "food_culture" => [
        %{id: "tf1", text: "Traditional Japanese fermented soybeans are called?", options: [%{id: "A", text: "Miso"}, %{id: "B", text: "Natto"}, %{id: "C", text: "Tempeh"}, %{id: "D", text: "Kimchi"}], correct: "B"},
        %{id: "tf2", text: "Which country is the largest producer of coffee beans?", options: [%{id: "A", text: "Vietnam"}, %{id: "B", text: "Colombia"}, %{id: "C", text: "Brazil"}, %{id: "D", text: "Ethiopia"}], correct: "C"},
        %{id: "tf3", text: "Pho is most associated with the cuisine of?", options: [%{id: "A", text: "Thailand"}, %{id: "B", text: "Vietnam"}, %{id: "C", text: "China"}, %{id: "D", text: "Japan"}], correct: "B"}
      ],
      "sports_lite" => [
        %{id: "tsp1", text: "How many players per team are on the court in basketball?", options: [%{id: "A", text: "4"}, %{id: "B", text: "5"}, %{id: "C", text: "6"}, %{id: "D", text: "7"}], correct: "B"},
        %{id: "tsp2", text: "The FIFA World Cup is held every …", options: [%{id: "A", text: "2 years"}, %{id: "B", text: "3 years"}, %{id: "C", text: "4 years"}, %{id: "D", text: "5 years"}], correct: "C"},
        %{id: "tsp3", text: "Tennis scores use 'love' to mean …", options: [%{id: "A", text: "Advantage"}, %{id: "B", text: "Deuce"}, %{id: "C", text: "Zero"}, %{id: "D", text: "Match point"}], correct: "C"}
      ],
      "technology" => [
        %{id: "tt1", text: "HTTP stands for …", options: [%{id: "A", text: "HyperText Transfer Protocol"}, %{id: "B", text: "High Transfer Text Process"}, %{id: "C", text: "Hosted Text Transmission Packet"}, %{id: "D", text: "Hybrid Terminal Transport Program"}], correct: "A"},
        %{id: "tt2", text: "Which company created the Linux kernel?", options: [%{id: "A", text: "Torvalds (personal project)"}, %{id: "B", text: "Microsoft"}, %{id: "C", text: "IBM"}, %{id: "D", text: "Apple"}], correct: "A"},
        %{id: "tt3", text: "What does CPU stand for?", options: [%{id: "A", text: "Central Processing Unit"}, %{id: "B", text: "Computer Personal Utility"}, %{id: "C", text: "Core Program Utility"}, %{id: "D", text: "Cached Processing Upper bus"}], correct: "A"}
      ]
    }
    |> ensure_min_questions_per_category(8)
  end

  defp ensure_min_questions_per_category(pools, min_n) do
    Enum.into(pools, %{}, fn {cat, qs} ->
      missing = max(min_n - length(qs), 0)

      generated =
        Enum.map(1..missing, fn i ->
          n = length(qs) + i
          {prompt, choices} = generated_truth_prompt_and_choices(cat, n)
          correct = "A"
          %{
            id: "#{cat}_gen_#{n}",
            text: prompt,
            options: [
              %{id: "A", text: Enum.at(choices, 0)},
              %{id: "B", text: Enum.at(choices, 1)},
              %{id: "C", text: Enum.at(choices, 2)},
              %{id: "D", text: Enum.at(choices, 3)}
            ],
            correct: correct
          }
        end)

      {cat, qs ++ generated}
    end)
  end

  defp next_option_id(existing_ids) do
    letters = 0..25 |> Enum.map(fn i -> <<?A + i>> end)
    Enum.find(letters, fn l -> l not in existing_ids end) || "Z#{System.unique_integer([:positive])}"
  end

  defp generated_truth_prompt_and_choices(cat, _n) do
    case cat do
      "technology" ->
        {"Which term is directly related to computing?", ["Database", "Palm Tree", "Waterfall", "Volcano"]}
      "geography" ->
        {"Which place is a country?", ["Peru", "Sahara", "Amazon", "Alps"]}
      "history" ->
        {"Which item is a historical era?", ["Renaissance", "Microwave Age", "Plastic Era", "Wi-Fi Era"]}
      "sports_lite" ->
        {"Which of these is an Olympic sport?", ["Archery", "Chessboxing", "Esports", "Tag"]}
      "food_culture" ->
        {"Which is a fermented food?", ["Kimchi", "Marshmallow", "Ketchup", "Granola Bar"]}
      "pop_culture" ->
        {"Which is a film genre?", ["Science Fiction", "Spreadsheet", "Blueprint", "Algorithm"]}
      "science_lite" ->
        {"Which is a planet in our solar system?", ["Mercury", "Polaris", "Orion", "Andromeda"]}
      "social_stats" ->
        {"Which is a common social network?", ["Instagram", "PowerPoint", "Excel", "Photoshop"]}
      "weird_facts" ->
        {"Which animal can regenerate lost limbs?", ["Starfish", "Panda", "Penguin", "Camel"]}
      _ ->
        {"Which answer is most likely correct?", ["Option A", "Option B", "Option C", "Option D"]}
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
end
