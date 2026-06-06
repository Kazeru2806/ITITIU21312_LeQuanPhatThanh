defmodule VnParty.Game.Presence do
  @moduledoc """
  Tracks player connection flags and lobby roster broadcasts.
  """

  alias VnParty.Game
  alias VnParty.Game.Player

  @doc "Player reconnected to the channel."
  def mark_connected(player_id) when is_binary(player_id) do
    :ets.delete(:player_absent, player_id)

    case :ets.lookup(:player_connection_cache, player_id) do
      [{_, true}] ->
        :ok

      _ ->
        :ets.insert(:player_connection_cache, {player_id, true})
        Game.update_player_connection(player_id, true)
    end

    player_id
  end

  @doc "Player left the channel (tab closed). Lobby seats are removed immediately via `Game.player_left/2`."
  def mark_disconnected(player_id) when is_binary(player_id) do
    :ets.delete(:player_connection_cache, player_id)
    Game.update_player_connection(player_id, false)
    player_id
  end

  @doc "Remove disconnected lobby seats before starting a game."
  def kick_stale_absent_players(room_id) do
    room_id
    |> Game.list_players()
    |> Enum.filter(fn p -> not p.connected end)
    |> Enum.each(fn p -> Game.remove_player_from_room(p.id) end)
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
          :ets.delete(:player_absent, absent.id)
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

  @doc "Formatted player list for WebSocket payloads."
  def format_players_public(room_id, players \\ nil) do
    players = players || Game.list_players(room_id)
    mode = Game.room_mode(Game.get_room!(room_id))

    format_players(players, mode)
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
