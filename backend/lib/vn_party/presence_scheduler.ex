defmodule VnParty.PresenceScheduler do
  @moduledoc """
  Debounces disconnects (tab background / brief network loss) and runs absent kicks.
  """
  use GenServer

  alias VnParty.Game
  alias VnParty.Game.Presence
  alias VnPartyWeb.Endpoint

  @disconnect_grace_ms 45_000
  @absent_kick_ms 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  def touch(player_id) when is_binary(player_id) do
    GenServer.cast(__MODULE__, {:touch, player_id})
  end

  def cancel(player_id) when is_binary(player_id) do
    :ets.delete(:pending_disconnect, player_id)
    GenServer.cast(__MODULE__, {:cancel, player_id})
  end

  def schedule_disconnect(player_id, room_id, room_code, delay_ms \\ @disconnect_grace_ms) do
    :ets.insert(:pending_disconnect, {player_id, room_id})
    GenServer.cast(__MODULE__, {:schedule_disconnect, player_id, room_id, room_code, delay_ms})
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:touch, player_id}, state) do
    cancel_timer(state, player_id)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:cancel, player_id}, state) do
    {:noreply, cancel_timer(state, player_id)}
  end

  @impl true
  def handle_cast({:schedule_disconnect, player_id, room_id, room_code, delay_ms}, state) do
    state = cancel_timer(state, player_id)
    ref = Process.send_after(self(), {:disconnect, player_id, room_id, room_code}, delay_ms)
    {:noreply, Map.put(state, player_id, %{disconnect_ref: ref, kick_ref: nil})}
  end

  @impl true
  def handle_info({:disconnect, player_id, room_id, room_code}, state) do
    state = Map.update(state, player_id, %{disconnect_ref: nil, kick_ref: nil}, fn
      %{kick_ref: kick} = m -> %{m | disconnect_ref: nil}
      _ -> %{disconnect_ref: nil, kick_ref: nil}
    end)

    # Reconnected during grace — cancel cleared the pending flag.
    if :ets.lookup(:pending_disconnect, player_id) == [] do
      {:noreply, Map.delete(state, player_id)}
    else
    :ets.delete(:pending_disconnect, player_id)

    player = Game.get_player!(player_id)
    room = Game.get_room!(room_id)

    Presence.mark_disconnected(player_id)
    :ets.insert(:player_absent, {player_id, %{since: System.monotonic_time(:millisecond)}})
    Game.mark_skip_next_round(room_id, player_id)

    {:ok, new_host} = Game.ensure_connected_host(room_id)

    if new_host do
      Endpoint.broadcast("game:#{room_code}", "host_changed", %{
        host_id: new_host.id,
        host_nickname: new_host.nickname
      })
    end

    players = Game.list_players(room_id)

    payload = %{
      player_id: player_id,
      nickname: player.nickname,
      players: format_players(players, Game.room_mode(room))
    }

    Endpoint.broadcast("game:#{room_code}", "player_disconnected", payload)
    Endpoint.broadcast("display:#{room_code}", "display:player_disconnected", payload)
    Presence.broadcast_players_sync(room_id)

    kick_ref = Process.send_after(self(), {:kick, player_id, room_id}, @absent_kick_ms)

    {:noreply,
     Map.update(state, player_id, %{disconnect_ref: nil, kick_ref: kick_ref}, fn m ->
       Map.put(m, :kick_ref, kick_ref)
     end)}
    end
  rescue
    Ecto.NoResultsError ->
      {:noreply, Map.delete(state, player_id)}
  end

  @impl true
  def handle_info({:kick, player_id, room_id}, state) do
    state = Map.delete(state, player_id)

    case Game.get_player(player_id) do
      nil ->
        :ok

      player ->
        if not player.connected do
          Game.remove_player_from_room(player_id)
          Presence.broadcast_players_sync(room_id)
        end
    end

    {:noreply, state}
  end

  defp cancel_timer(state, player_id) do
    case Map.get(state, player_id) do
      %{disconnect_ref: ref} when is_reference(ref) ->
        Process.cancel_timer(ref)

      _ ->
        :ok
    end

    case Map.get(state, player_id) do
      %{kick_ref: ref} when is_reference(ref) ->
        Process.cancel_timer(ref)

      _ ->
        :ok
    end

    Map.delete(state, player_id)
  end

  defp format_players(players, mode) do
    Enum.map(players, fn p ->
      %{
        id: p.id,
        nickname: p.nickname,
        score: p.score,
        connected: p.connected,
        is_host: p.is_host,
        status: presence_status(p)
      }
    end)
  end

  defp presence_status(%{connected: true}), do: "online"
  defp presence_status(%{connected: false}), do: "absent"

  # Game.get_player/1 — add if missing
end
