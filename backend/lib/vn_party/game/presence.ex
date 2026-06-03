defmodule VnParty.Game.Presence do
  @moduledoc """
  Tracks disconnect timers, host transfer side-effects, and absent-player eviction.
  """

  alias VnParty.Repo
  alias VnParty.Game
  alias VnParty.Game.Player

  @absent_kick_ms 30_000

  @doc "Player reconnected to the channel."
  def mark_connected(player_id) when is_binary(player_id) do
    cancel_absent_timer(player_id)
    Game.update_player_connection(player_id, true)
    player_id
  end

  @doc "Player left the channel; start absent kick timer."
  def mark_disconnected(player_id) when is_binary(player_id) do
    Game.update_player_connection(player_id, false)
    schedule_absent_kick(player_id)
    player_id
  end

  @doc "Remove players who stayed disconnected past the kick window."
  def kick_stale_absent_players(room_id) do
    room_id
    |> Game.list_players()
    |> Enum.filter(fn p -> not p.connected end)
    |> Enum.each(fn p ->
      cancel_absent_timer(p.id)
      Game.remove_player_from_room(p.id)
    end)
  end

  @doc """
  If room is at capacity, remove the longest-absent disconnected player to make room.
  Returns `:ok` or `{:error, :room_full}`.
  """
  def make_room_for_join(room_id) do
    room = Game.get_room!(room_id)
    players = Game.list_players(room_id)

    if length(players) < room.max_players do
      :ok
    else
      case oldest_absent_player(players) do
        nil -> {:error, :room_full}
        absent ->
          cancel_absent_timer(absent.id)
          Game.remove_player_from_room(absent.id)
          :ok
      end
    end
  end

  defp oldest_absent_player(players) do
    players
    |> Enum.filter(fn p -> not p.connected end)
    |> Enum.sort_by(fn p ->
      case :ets.lookup(:player_absent, p.id) do
        [{_, since}] -> since
        [] -> 0
      end
    end)
    |> List.first()
  end

  defp schedule_absent_kick(player_id) do
    cancel_absent_timer(player_id)
    since = System.monotonic_time(:millisecond)

    ref =
      Process.spawn(fn ->
        Process.sleep(@absent_kick_ms)
        maybe_kick_absent_player(player_id)
      end)

    :ets.insert(:player_absent, {player_id, %{since: since, timer: ref}})
  end

  defp maybe_kick_absent_player(player_id) do
    player = Repo.get(Player, player_id)

    cond do
      is_nil(player) ->
        :ets.delete(:player_absent, player_id)

      player.connected ->
        :ets.delete(:player_absent, player_id)

      true ->
        room_id = player.room_id
        Game.remove_player_from_room(player_id)
        :ets.delete(:player_absent, player_id)
        broadcast_players_sync(room_id)
    end
  rescue
    _ -> :ok
  end

  defp cancel_absent_timer(player_id) do
    case :ets.lookup(:player_absent, player_id) do
      [{^player_id, %{timer: pid}}] when is_integer(pid) ->
        if Process.alive?(pid), do: Process.exit(pid, :kill)
        :ets.delete(:player_absent, player_id)

      _ ->
        :ets.delete(:player_absent, player_id)
    end
  end

  @doc "Broadcast full player list to game + display channels."
  def broadcast_players_sync(room_id) do
    room = Game.get_room!(room_id)
    players = Game.list_players(room_id)
    mode = Game.room_mode(room)

    payload = %{
      players: format_players(players, mode),
      host_id: host_id(players)
    }

    VnPartyWeb.Endpoint.broadcast("game:#{room.code}", "players_sync", payload)
    VnPartyWeb.Endpoint.broadcast("display:#{room.code}", "display:players_sync", payload)
    payload
  end

  defp host_id(players) do
    case Enum.find(players, & &1.is_host) do
      nil -> nil
      p -> p.id
    end
  end

  defp format_players(players, _mode) do
    Enum.map(players, fn p ->
      %{
        id: p.id,
        nickname: p.nickname,
        score: p.score,
        connected: p.connected,
        is_host: p.is_host,
        status: if(p.connected, do: "online", else: "absent")
      }
    end)
  end
end
