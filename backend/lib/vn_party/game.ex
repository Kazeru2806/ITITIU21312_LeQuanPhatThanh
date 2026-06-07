defmodule VnParty.Game do
  @moduledoc """
  The Game context - handles all game-related business logic.
  """

  import Ecto.Query, warn: false
  alias VnParty.Repo
  alias VnParty.Game.{Room, Player, Event, AnswerCommit, Snapshot}
  alias VnParty.Blockchain.AuditTrail

  # ============================================================================
  # ROOM OPERATIONS
  # ============================================================================

  @doc """
    Creates a new game room.
    Returns {:ok, room} or {:error, changeset}
    """

  def create_room(attrs \\ %{}) do
    code = Room.generate_code()

    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    mode = Map.get(attrs, "mode", "classic")
    total_rounds_default = if mode == "truth_collapse", do: 8, else: 5

    # Convert all keys to atoms and merge with defaults
    attrs =
      attrs
      |> Map.put("code", code)
      |> Map.put_new("state", "lobby")
      |> Map.put_new("total_rounds", total_rounds_default)
      |> Map.put_new("max_players", 8)
      |> Map.update("config", %{"mode" => mode}, fn config ->
        config = Map.new(config, fn {k, v} -> {to_string(k), v} end)
        Map.put_new(config, "mode", mode)
      end)

    if cache_enabled?() do
      room = %Room{
        id: Ecto.UUID.generate(),
        code: code,
        state: Map.get(attrs, "state"),
        total_rounds: Map.get(attrs, "total_rounds"),
        max_players: Map.get(attrs, "max_players"),
        config: Map.get(attrs, "config"),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
      :ets.insert(:room_cache, {room.code, room})
      :ets.insert(:room_cache, {room.id, room})
      :ets.insert(:room_players_cache, {room.id, []})
      create_event(room.id, "room_created", %{code: code})
      {:ok, room}
    else
      %Room{}
      |> Room.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, room} ->
          # Log room creation event
          create_event(room.id, "room_created", %{code: code})
          {:ok, room}
        error -> error
      end
    end
  end

  def room_mode(room) do
    case room.config do
      %{"mode" => mode} when is_binary(mode) -> mode
      %{mode: mode} when is_binary(mode) -> mode
      _ -> "classic"
    end
  end

  @doc """
  Gets a room by ID. Raises if not found.
  """
  def get_room!(id) do
    if cache_enabled?() do
      case :ets.lookup(:room_cache, id) do
        [{_, room}] -> room
        _ ->
          room = Repo.get!(Room, id)
          :ets.insert(:room_cache, {id, room})
          :ets.insert(:room_cache, {room.code, room})
          room
      end
    else
      Repo.get!(Room, id)
    end
  end

  @doc """
  Gets a room by code. Returns nil if not found.
  """
  def get_room_by_code(code) do
    code_up = String.upcase(code)
    if cache_enabled?() do
      case :ets.lookup(:room_cache, code_up) do
        [{_, room}] -> room
        _ ->
          case Repo.get_by(Room, code: code_up) do
            nil -> nil
            room ->
              :ets.insert(:room_cache, {code_up, room})
              :ets.insert(:room_cache, {room.id, room})
              room
          end
      end
    else
      Repo.get_by(Room, code: code_up)
    end
  end

  @doc """
  Gets a room by code with players preloaded.
  """
  def get_room_by_code_with_players(code) do
    code_up = String.upcase(code)
    if cache_enabled?() do
      case get_room_by_code(code_up) do
        nil -> nil
        room ->
          players = list_players(room.id)
          %{room | players: players}
      end
    else
      case get_room_by_code(code_up) do
        nil -> nil
        room -> Repo.preload(room, :players)
      end
    end
  end

  @doc """
  Updates a room's state.
  """
  def update_room_state(room, new_state) do
    if cache_enabled?() do
      updated_room = %{room | state: new_state}
      :ets.insert(:room_cache, {updated_room.code, updated_room})
      :ets.insert(:room_cache, {updated_room.id, updated_room})
      create_event(room.id, "state_changed", %{
        old_state: room.state,
        new_state: new_state
      })
      {:ok, updated_room}
    else
      room
      |> Room.update_state_changeset(new_state)
      |> Repo.update()
      |> case do
        {:ok, updated_room} ->
          create_event(room.id, "state_changed", %{
            old_state: room.state,
            new_state: new_state
          })
          {:ok, updated_room}
        error -> error
      end
    end
  end

  @doc """
  Advances room to the next round.
  """
  def advance_round(room) do
    if cache_enabled?() do
      updated_room = %{room | current_round: room.current_round + 1}
      :ets.insert(:room_cache, {updated_room.code, updated_room})
      :ets.insert(:room_cache, {updated_room.id, updated_room})
      create_event(room.id, "round_started", %{round: updated_room.current_round})
      {:ok, updated_room}
    else
      room
      |> Room.advance_round_changeset()
      |> Repo.update()
      |> case do
        {:ok, updated_room} ->
          create_event(room.id, "round_started", %{round: updated_room.current_round})
          {:ok, updated_room}
        error -> error
      end
    end
  end

  @doc """
  Starts a game.
  """
  def start_game(room_id) do
    room = get_room!(room_id)

    if cache_enabled?() do
      updated_room = %{room | state: "round_start", current_round: 1, started_at: DateTime.utc_now()}
      :ets.insert(:room_cache, {updated_room.code, updated_room})
      :ets.insert(:room_cache, {updated_room.id, updated_room})
      create_event(room.id, "game_started", %{})
      {:ok, updated_room}
    else
      room
      |> Room.changeset(%{
        state: "round_start",
        current_round: 1,
        started_at: DateTime.utc_now()
      })
      |> Repo.update()
      |> case do
        {:ok, updated_room} ->
          create_event(room.id, "game_started", %{})
          {:ok, updated_room}
        error -> error
      end
    end
  end

  # ============================================================================
  # PLAYER OPERATIONS
  # ============================================================================

  @doc """
  Joins a player to a room. Pass `"player_id"` in attrs to reconnect an existing seat.
  """
  def join_room(room_code, nickname, attrs \\ %{}) do
    attrs = normalize_join_attrs(attrs)
    player_id = Map.get(attrs, "player_id")

    with {:ok, room} <- fetch_room_by_code(room_code) do
      case rejoin_player(room, player_id, nickname) do
        {:ok, player} ->
          create_event(room.id, "player_rejoined", %{
            player_id: player.id,
            nickname: nickname
          }, player.id)
          {:ok, player}

        {:error, _} = err ->
          err

        :not_rejoin ->
          if room.state != "lobby" do
            {:error, :game_in_progress}
          else
          with :ok <- VnParty.Game.Presence.make_room_for_join(room.id),
               {:ok, _} <- check_room_capacity(room),
               {:ok, player} <- create_player(room, nickname, attrs) do
            create_event(room.id, "player_joined", %{
              player_id: player.id,
              nickname: nickname
            }, player.id)
            {:ok, player}
          end
          end
      end
    end
  end

  defp normalize_join_attrs(attrs) when is_map(attrs) do
    attrs
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
    |> Map.new()
  end

  defp rejoin_player(_room, nil, _nickname), do: :not_rejoin

  defp rejoin_player(room, player_id, nickname) when is_binary(player_id) do
    case get_player(player_id) do
      %Player{room_id: room_id, nickname: existing} when room_id == room.id ->
        if String.trim(existing) != String.trim(nickname) do
          {:error, :nickname_mismatch}
        else
          VnParty.Game.Presence.mark_connected(player_id)
          player = get_player!(player_id)

          case player
               |> Player.changeset(%{nickname: nickname, connected: true})
               |> Repo.update() do
            {:ok, updated} ->
              update_player_in_cache(updated)
              {:ok, updated}
            {:error, _} ->
              update_player_in_cache(player)
              {:ok, player}
          end
        end

      _ ->
        :not_rejoin
    end
  end

  @doc """
  Players who disconnect mid-game skip the next round (reconnect can resume after that).
  """
  def mark_skip_next_round(room_id, player_id) do
    room = get_room!(room_id)

    if room.state not in ["lobby", "game_end"] and room.current_round > 0 do
      :ets.insert(:player_round_skip, {player_id, room.current_round + 1})
    end

    :ok
  end

  def eligible_for_round?(player_id, round) when is_integer(round) do
    case :ets.lookup(:player_round_skip, player_id) do
      [] -> true
      [{_, skip_from}] -> round > skip_from
    end
  end

  def round_active_players(room_id, round) do
    room_id
    |> list_players()
    |> Enum.filter(fn p -> p.connected and eligible_for_round?(p.id, round) end)
  end

  @doc """
  Ends the game early and returns formatted leaderboard entries.
  """
  def end_game_early(room_id) do
    room = get_room!(room_id)

    with {:ok, room} <- update_room_state(room, "game_end") do
      players = list_players(room_id)
      leaderboard = format_leaderboard_for_end(players)

      {:ok,
       %{
         room: room,
         final_scores: leaderboard,
         winner: List.first(leaderboard)
       }}
    end
  end

  defp format_leaderboard_for_end(players) do
    players
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.map(fn p ->
      %{player_id: p.id, nickname: p.nickname, score: p.score}
    end)
  end

  defp fetch_room_by_code(code) do
    case get_room_by_code(code) do
      nil -> {:error, :room_not_found}
      room -> {:ok, room}
    end
  end

  defp check_room_capacity(room) do
    player_count = count_players_in_room(room.id)

    if player_count >= room.max_players do
      {:error, :room_full}
    else
      {:ok, room}
    end
  end

  defp create_player(room, nickname, attrs) do
    attrs =
      attrs
      |> Map.put(:room_id, room.id)
      |> Map.put(:nickname, nickname)
      |> Map.put(:joined_at, DateTime.utc_now())
      |> Map.put(:is_host, count_players_in_room(room.id) == 0)

    if cache_enabled?() do
      player = %Player{
        id: Ecto.UUID.generate(),
        room_id: room.id,
        nickname: nickname,
        is_host: Map.get(attrs, :is_host),
        joined_at: DateTime.utc_now(),
        connected: true,
        score: 0,
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
      update_player_in_cache(player)
      {:ok, player}
    else
      %Player{}
      |> Player.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, player} ->
          update_player_in_cache(player)
          {:ok, player}
        error -> error
      end
    end
  end

  @doc """
  Gets a player by ID.
  """
  def get_player!(id) do
    if cache_enabled?() do
      case :ets.lookup(:player_cache, id) do
        [{_, player}] -> player
        _ ->
          player = Repo.get!(Player, id)
          :ets.insert(:player_cache, {id, player})
          player
      end
    else
      Repo.get!(Player, id)
    end
  end

  def get_player(id) do
    if cache_enabled?() do
      case :ets.lookup(:player_cache, id) do
        [{_, player}] -> player
        _ ->
          case Repo.get(Player, id) do
            nil -> nil
            player ->
              :ets.insert(:player_cache, {id, player})
              player
          end
      end
    else
      Repo.get(Player, id)
    end
  end

  @doc """
  Lists all players in a room.
  """
  def list_players(room_id) do
    if cache_enabled?() do
      case :ets.lookup(:room_players_cache, room_id) do
        [{_, players}] ->
          Enum.sort(players, fn p1, p2 ->
            cond do
              p1.score != p2.score -> p1.score > p2.score
              true -> DateTime.compare(p1.joined_at, p2.joined_at) != :gt
            end
          end)
        _ ->
          players =
            Player
            |> where([p], p.room_id == ^room_id)
            |> order_by([p], desc: p.score, asc: p.joined_at)
            |> Repo.all()
          :ets.insert(:room_players_cache, {room_id, players})
          Enum.each(players, fn p -> :ets.insert(:player_cache, {p.id, p}) end)
          players
      end
    else
      Player
      |> where([p], p.room_id == ^room_id)
      |> order_by([p], desc: p.score, asc: p.joined_at)
      |> Repo.all()
    end
  end

  @doc """
  Counts players in a room.
  """
  def count_players_in_room(room_id) do
    if cache_enabled?() do
      length(list_players(room_id))
    else
      Player
      |> where([p], p.room_id == ^room_id)
      |> Repo.aggregate(:count)
    end
  end

  @doc """
  Updates player connection status.
  """
  def update_player_connection(player_id, connected) do
    player = get_player!(player_id)

    if cache_enabled?() do
      updated = %{player | connected: connected, last_seen_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
      update_player_in_cache(updated)
      {:ok, updated}
    else
      player
      |> Player.update_connection_changeset(connected)
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          update_player_in_cache(updated)
          {:ok, updated}
        error -> error
      end
    end
  end

  @doc """
  Ensures there is a connected host for the room.

  If the current host disconnects, transfers host role to another connected player.
  Falls back to the first remaining player if nobody is currently connected.
  """
  def ensure_connected_host(room_id) do
    if cache_enabled?() do
      players = list_players(room_id)
      has_connected_host? = Enum.any?(players, fn p -> p.is_host and p.connected end)

      if has_connected_host? do
        {:ok, nil}
      else
        players_dehosted = Enum.map(players, fn p -> %{p | is_host: false} end)
        new_host = Enum.find(players_dehosted, & &1.connected)

        players_updated =
          if new_host do
            Enum.map(players_dehosted, fn p ->
              if p.id == new_host.id do
                %{p | is_host: true}
              else
                p
              end
            end)
          else
            players_dehosted
          end

        :ets.insert(:room_players_cache, {room_id, players_updated})
        Enum.each(players_updated, fn p -> :ets.insert(:player_cache, {p.id, p}) end)

        new_host_final = if new_host, do: %{new_host | is_host: true}, else: nil
        {:ok, new_host_final}
      end
    else
      Repo.transaction(fn ->
        players = list_players(room_id)

        has_connected_host? =
          Enum.any?(players, fn p -> p.is_host and p.connected end)

        if has_connected_host? do
          nil
        else
          from(p in Player, where: p.room_id == ^room_id)
          |> Repo.update_all(set: [is_host: false])

          new_host = Enum.find(players, & &1.connected)

          if new_host do
            case new_host |> Player.make_host_changeset() |> Repo.update() do
              {:ok, host} -> host
              {:error, _} -> nil
            end
          else
            nil
          end
        end
      end)
      |> case do
        {:ok, host} ->
          if cache_enabled?() do
            players =
              Player
              |> where([p], p.room_id == ^room_id)
              |> order_by([p], desc: p.score, asc: p.joined_at)
              |> Repo.all()
            :ets.insert(:room_players_cache, {room_id, players})
            Enum.each(players, fn p -> :ets.insert(:player_cache, {p.id, p}) end)
          end
          {:ok, host}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Updates player score.
  """
  def update_player_score(player_id, points) do
    player = get_player!(player_id)

    if cache_enabled?() do
      new_score = max(0, player.score + points)
      updated = %{player | score: new_score, updated_at: DateTime.utc_now()}
      update_player_in_cache(updated)
      {:ok, updated}
    else
      player
      |> Player.update_score_changeset(points)
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          update_player_in_cache(updated)
          {:ok, updated}
        error -> error
      end
    end
  end

  @doc """
  Removes a player from a room.
  """
  def remove_player_from_room(player_id) do
    player = get_player!(player_id)
    room_id = player.room_id

    if cache_enabled?() do
      :ets.delete(:player_absent, player_id)
      :ets.delete(:player_round_skip, player_id)
      :ets.delete(:player_cache, player_id)

      players =
        case :ets.lookup(:room_players_cache, room_id) do
          [{_, list}] -> list
          _ -> []
        end
      updated_players = Enum.reject(players, fn p -> p.id == player_id end)
      :ets.insert(:room_players_cache, {room_id, updated_players})

      new_host =
        case ensure_connected_host(room_id) do
          {:ok, host} -> host
          _ -> nil
        end

      VnParty.Game.Presence.broadcast_players_sync(room_id)
      {:ok, player, new_host}
    else
      case Repo.delete(player) do
        {:ok, deleted} ->
          :ets.delete(:player_absent, player_id)
          :ets.delete(:player_round_skip, player_id)

          if cache_enabled?() do
            :ets.delete(:player_cache, player_id)
            players =
              case :ets.lookup(:room_players_cache, room_id) do
                [{_, list}] -> list
                _ -> []
              end
            updated_players = Enum.reject(players, fn p -> p.id == player_id end)
            :ets.insert(:room_players_cache, {room_id, updated_players})
          end

          new_host =
            case ensure_connected_host(room_id) do
              {:ok, host} -> host
              _ -> nil
            end

          VnParty.Game.Presence.broadcast_players_sync(room_id)
          {:ok, deleted, new_host}

        error ->
          error
      end
    end
  end

  @doc """
  Player left (tab closed, back button, or Return to main screen).
  Removes them from the lobby immediately and transfers host if needed.
  """
  def player_left(player_id, room_code) when is_binary(player_id) do
    case get_player(player_id) do
      nil ->
        :ok

      %Player{} = player ->
        do_player_left(player, room_code)
    end
  end

  defp do_player_left(player, room_code) do
    player_id = player.id
    room_id = player.room_id
    nickname = player.nickname

    case remove_player_from_room(player_id) do
      {:ok, _deleted, new_host} ->
        create_event(room_id, "player_left", %{player_id: player_id, nickname: nickname}, player_id)

        if new_host do
          VnPartyWeb.Endpoint.broadcast("game:#{room_code}", "host_changed", %{
            host_id: new_host.id,
            host_nickname: new_host.nickname
          })
        end

        VnParty.Game.Presence.broadcast_players_sync(room_id)

        players = list_players(room_id)

        payload = %{
          player_id: player_id,
          nickname: nickname,
          players: VnParty.Game.Presence.format_players_public(room_id, players)
        }

        VnPartyWeb.Endpoint.broadcast("game:#{room_code}", "player_left", payload)
        VnPartyWeb.Endpoint.broadcast("display:#{room_code}", "display:player_left", payload)

        Phoenix.PubSub.broadcast(VnParty.PubSub, "room:#{room_id}:internal", {:check_all_committed, room_id})

        {:ok, new_host}

      error ->
        error
    end
  end

  @doc """
  Host display closed the room — end game and notify all clients.
  """
  def close_room_session(room_id) do
    room = get_room!(room_id)
    code = room.code

    if room.state not in ["lobby", "game_end"] do
      end_game_early(room_id)
    end

    # Mark room closed so late joins and stale sockets cannot continue.
    room
    |> Room.changeset(%{state: "game_end", current_round: 0})
    |> Repo.update()

    payload = %{
      reason: "room_closed",
      message: "The host ended this room. Returning to the main screen.",
      redirect_seconds: 5
    }

    VnPartyWeb.Endpoint.broadcast("game:#{code}", "room_closed", payload)
    VnPartyWeb.Endpoint.broadcast("display:#{code}", "display:room_closed", payload)

    create_event(room_id, "room_closed", %{reason: payload.reason}, nil)

    {:ok, room}
  end

  @doc "Returns the committed answer text (DB or in-memory pending store)."
  def commit_answer_text(%{answer: answer}) when is_binary(answer), do: answer

  def commit_answer_text(%{answer: nil, room_id: room_id, player_id: player_id, round: round}) do
    case :ets.lookup(:pending_answers, {room_id, player_id, round}) do
      [{_, %{answer: answer}}] -> answer
      _ -> nil
    end
  end

  def commit_answer_text(commit), do: commit.answer

  # ============================================================================
  # EVENT SOURCING
  # ============================================================================

  @doc """
  Creates a new event in the event log.
  """
  def create_event(room_id, event_type, payload, player_id \\ nil) do
    seq = get_next_sequence_number(room_id)

    if cache_enabled?() do
      event = %Event{
        id: Ecto.UUID.generate(),
        room_id: room_id,
        player_id: player_id,
        event_type: event_type,
        seq: seq,
        payload: payload,
        metadata: %{
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        },
        inserted_at: DateTime.utc_now()
      }

      events =
        case :ets.lookup(:room_events_cache, room_id) do
          [{_, list}] -> list
          _ -> []
        end
      :ets.insert(:room_events_cache, {room_id, events ++ [event]})

      AuditTrail.on_event(event)
      {:ok, event}
    else
      %Event{}
      |> Event.changeset(%{
        room_id: room_id,
        player_id: player_id,
        event_type: event_type,
        seq: seq,
        payload: payload,
        metadata: %{
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      })
      |> Repo.insert()
      |> case do
        {:ok, event} ->
          AuditTrail.on_event(event)
          {:ok, event}

        error ->
          error
      end
    end
  end

  def list_blockchain_anchors(room_id), do: AuditTrail.list_room_anchors(room_id)

  @doc """
  Gets all events for a room since a given sequence number.
  """
  def get_events_since(room_id, since_seq) do
    if cache_enabled?() do
      case :ets.lookup(:room_events_cache, room_id) do
        [{_, list}] ->
          list |> Enum.filter(fn e -> e.seq > since_seq end)
        _ ->
          []
      end
    else
      Event
      |> where([e], e.room_id == ^room_id and e.seq > ^since_seq)
      |> order_by([e], asc: e.seq)
      |> Repo.all()
    end
  end

  @doc """
  Gets the next sequence number for a room.
  """
  def get_next_sequence_number(room_id) do
    case :ets.lookup(:room_event_seq, room_id) do
      [{^room_id, _seq}] ->
        :ets.update_counter(:room_event_seq, room_id, {2, 1})

      [] ->
        db_seq =
          case Repo.one(
            from e in Event,
            where: e.room_id == ^room_id,
            select: max(e.seq)
          ) do
            nil -> 1
            max_seq -> max_seq + 1
          end

        if :ets.insert_new(:room_event_seq, {room_id, db_seq}) do
          db_seq
        else
          :ets.update_counter(:room_event_seq, room_id, {2, 1})
        end
    end
  end

  # ============================================================================
  # COMMIT-REVEAL MECHANISM
  # ============================================================================

  @doc """
  Commits a player's answer (Phase 1 of commit-reveal).
  """
  def commit_answer(room_id, player_id, round, question_id, commit_hash) do
    if cache_enabled?() do
      commit = %AnswerCommit{
        id: Ecto.UUID.generate(),
        room_id: room_id,
        player_id: player_id,
        round: round,
        question_id: question_id,
        commit_hash: commit_hash,
        committed_at: DateTime.utc_now(),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        is_valid: true
      }

      list =
        case :ets.lookup(:answer_commits_cache, {room_id, round}) do
          [{_, existing}] -> existing
          _ -> []
        end

      list = Enum.reject(list, fn c -> c.player_id == player_id end)
      :ets.insert(:answer_commits_cache, {{room_id, round}, list ++ [commit]})
      :ets.insert(:answer_commits_cache, {commit.id, commit})

      create_event(room_id, "answer_committed", %{
        player_id: player_id,
        round: round
      }, player_id)
      {:ok, commit}
    else
      %AnswerCommit{}
      |> AnswerCommit.commit_changeset(%{
        room_id: room_id,
        player_id: player_id,
        round: round,
        question_id: question_id,
        commit_hash: commit_hash,
        committed_at: DateTime.utc_now()
      })
      |> Repo.insert()
      |> case do
        {:ok, commit} ->
          create_event(room_id, "answer_committed", %{
            player_id: player_id,
            round: round
          }, player_id)
          {:ok, commit}
        error -> error
      end
    end
  end

  @doc """
  Secure commit API used by channels and H3 attack simulations.

  Enforces:
  - replay protection (same commit_hash not reusable by same player in room)
  - late commit rejection (commit window closed)
  """
  def commit_answer_secure(room_id, player_id, round, question_id, commit_hash) do
    cond do
      replayed_commit_hash?(room_id, player_id, commit_hash) ->
        {:error, :replay_attack}

      not commit_window_open?(room_id, round) ->
        {:error, :late_commit}

      true ->
        with {:ok, commit} <- commit_answer(room_id, player_id, round, question_id, commit_hash) do
          delay_ms = commit_delay_ms(room_id, round)
          threshold_ms =
            case commit_window(room_id, round) do
              {:ok, %{time_limit_s: s}} when is_integer(s) -> max((s - 2) * 1000, 0)
              _ -> 13_000
            end

          violation = if is_integer(delay_ms) and delay_ms >= threshold_ms, do: "timing_manipulation", else: nil

          if cache_enabled?() do
            updated = %{commit | commit_delay_ms: delay_ms, violation_reason: violation}
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
            |> Ecto.Changeset.change(%{commit_delay_ms: delay_ms, violation_reason: violation})
            |> Repo.update()
          end
        end
    end
  end

  defp replayed_commit_hash?(room_id, player_id, commit_hash) do
    if cache_enabled?() do
      1..8
      |> Enum.flat_map(fn round ->
        case :ets.lookup(:answer_commits_cache, {room_id, round}) do
          [{_, list}] -> list
          _ -> []
        end
      end)
      |> Enum.any?(fn c -> c.player_id == player_id and c.commit_hash == commit_hash end)
    else
      AnswerCommit
      |> where([c], c.room_id == ^room_id and c.player_id == ^player_id and c.commit_hash == ^commit_hash)
      |> select([c], c.id)
      |> limit(1)
      |> Repo.one()
      |> case do
        nil -> false
        _ -> true
      end
    end
  end

  @doc """
  Records the question reveal timestamp and commit window length for a room+round.
  Used to enforce late-commit rejection and timing-manipulation detection.
  """
  def record_commit_window(room_id, round, time_limit_s) when is_integer(round) do
    :ets.insert(:commit_windows, {{room_id, round}, %{revealed_ms: System.system_time(:millisecond), time_limit_s: time_limit_s}})
    :ok
  end

  # Test helper: force a commit window (e.g., simulate expiry).
  def put_commit_window(room_id, round, revealed_ms, time_limit_s) do
    :ets.insert(:commit_windows, {{room_id, round}, %{revealed_ms: revealed_ms, time_limit_s: time_limit_s}})
    :ok
  end

  def commit_window(room_id, round) do
    case :ets.lookup(:commit_windows, {room_id, round}) do
      [{{^room_id, ^round}, meta}] when is_map(meta) -> {:ok, meta}
      _ -> :error
    end
  end

  def commit_window_open?(room_id, round) do
    case commit_window(room_id, round) do
      {:ok, %{revealed_ms: revealed_ms, time_limit_s: time_limit_s}} ->
        now = System.system_time(:millisecond)
        now <= revealed_ms + time_limit_s * 1000

      _ ->
        true
    end
  end

  def commit_delay_ms(room_id, round) do
    case commit_window(room_id, round) do
      {:ok, %{revealed_ms: revealed_ms}} ->
        System.system_time(:millisecond) - revealed_ms
      _ ->
        nil
    end
  end

  @doc """
  Verifies that the stored commit_hash matches the stored answer+salt.
  Returns true/false (never raises).
  """
  def commit_hash_valid?(%AnswerCommit{commit_hash: h, answer: a, salt: s})
      when is_binary(h) and is_binary(a) and is_binary(s) do
    AnswerCommit.generate_commit_hash(a, s) == h
  end

  def commit_hash_valid?(_), do: false

  @doc """
  If the commit has answer+salt but the hash doesn't match, flag it as invalid.
  Returns {:ok, updated_commit} or {:ok, original_commit}.
  """
  def flag_hash_tampering_if_any(%AnswerCommit{} = commit) do
    if commit.answer && commit.salt && not commit_hash_valid?(commit) do
      if cache_enabled?() do
        updated = %{commit | is_valid: false, violation_reason: "hash_tampering"}
        list =
          case :ets.lookup(:answer_commits_cache, {commit.room_id, commit.round}) do
            [{_, existing}] -> existing
            _ -> []
          end
        list = Enum.map(list, fn c -> if c.id == updated.id, do: updated, else: c end)
        :ets.insert(:answer_commits_cache, {{commit.room_id, commit.round}, list})
        :ets.insert(:answer_commits_cache, {updated.id, updated})
        {:ok, updated}
      else
        commit
        |> Ecto.Changeset.change(%{is_valid: false, violation_reason: "hash_tampering"})
        |> Repo.update()
      end
    else
      {:ok, commit}
    end
  end

  @doc """
  Reveals a player's answer (Phase 2 of commit-reveal).
  """
  def reveal_answer(commit_id, answer, salt) do
    if cache_enabled?() do
      case :ets.lookup(:answer_commits_cache, commit_id) do
        [{_, commit}] ->
          revealed_commit = %{commit | answer: answer, salt: salt, revealed_at: DateTime.utc_now()}
          revealed_commit =
            if commit_hash_valid?(revealed_commit) do
              revealed_commit
            else
              %{revealed_commit | is_valid: false, violation_reason: "hash_tampering"}
            end

          list =
            case :ets.lookup(:answer_commits_cache, {revealed_commit.room_id, revealed_commit.round}) do
              [{_, existing}] -> existing
              _ -> []
            end
          list = Enum.map(list, fn c -> if c.id == revealed_commit.id, do: revealed_commit, else: c end)
          :ets.insert(:answer_commits_cache, {{revealed_commit.room_id, revealed_commit.round}, list})
          :ets.insert(:answer_commits_cache, {revealed_commit.id, revealed_commit})

          if revealed_commit.is_valid do
            create_event(revealed_commit.room_id, "answer_revealed", %{
              player_id: revealed_commit.player_id,
              round: revealed_commit.round,
              is_valid: true
            }, revealed_commit.player_id)
            {:ok, revealed_commit}
          else
            {:error, :invalid_commit}
          end

        _ ->
          {:error, :not_found}
      end
    else
      commit = Repo.get!(AnswerCommit, commit_id)

      commit
      |> AnswerCommit.reveal_changeset(%{
        answer: answer,
        salt: salt,
        revealed_at: DateTime.utc_now()
      })
      |> Repo.update()
      |> case do
        {:ok, revealed_commit} ->
          if revealed_commit.is_valid do
            create_event(revealed_commit.room_id, "answer_revealed", %{
              player_id: revealed_commit.player_id,
              round: revealed_commit.round,
              is_valid: true
            }, revealed_commit.player_id)
            {:ok, revealed_commit}
          else
            {:error, :invalid_commit}
          end
        error -> error
      end
    end
  end

  @doc """
  Gets all commits for a specific round in a room.
  """
  def get_round_commits(room_id, round) do
    if cache_enabled?() do
      case :ets.lookup(:answer_commits_cache, {room_id, round}) do
        [{_, list}] -> list
        _ -> []
      end
    else
      AnswerCommit
      |> where([c], c.room_id == ^room_id and c.round == ^round)
      |> Repo.all()
    end
  end

  # ============================================================================
  # SNAPSHOT MANAGEMENT
  # ============================================================================

  @doc """
  Creates a snapshot of current game state.
  """
  def create_snapshot(room_id) do
    if cache_enabled?() do
      {:ok, %Snapshot{}}
    else
      room = get_room!(room_id) |> Repo.preload(:players)
      current_seq = get_next_sequence_number(room_id) - 1

      Snapshot.create_snapshot(room, room.players, current_seq)
      |> Repo.insert()
    end
  end

  @doc """
  Gets the latest snapshot for a room.
  """
  def get_latest_snapshot(room_id) do
    if cache_enabled?() do
      nil
    else
      Snapshot
      |> where([s], s.room_id == ^room_id)
      |> order_by([s], desc: s.seq)
      |> limit(1)
      |> Repo.one()
    end
  end

  defp cache_enabled? do
    Application.get_env(:vn_party, :cache_enabled, true)
  end

  defp update_player_in_cache(player) do
    if cache_enabled?() do
      :ets.insert(:player_cache, {player.id, player})
      case :ets.lookup(:room_players_cache, player.room_id) do
        [{_, list}] ->
          updated_list = [player | Enum.reject(list, fn p -> p.id == player.id end)]
          :ets.insert(:room_players_cache, {player.room_id, updated_list})
        _ ->
          # If not yet loaded, list_players will load and cache it on next call
          :ok
      end
    end
    player
  end
end
