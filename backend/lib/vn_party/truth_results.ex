defmodule VnParty.TruthResults do
  @moduledoc """
  Results-phase ready votes (Done button) for Truth Collapse.
  Shared by WebSocket channel and HTTP fallback API.
  """

  alias VnParty.Game
  alias VnPartyWeb.Endpoint
  alias Phoenix.PubSub

  @type ready_result :: %{
          received: true,
          already_ready: boolean(),
          distortion_note: String.t() | nil,
          progress: map()
        }

  @doc """
  Records a player ready for the next round during results phase.
  Idempotent: duplicate calls return success.
  """
  def record_results_ready(room_id, player_id, round \\ nil) do
    room = Game.get_room!(room_id)

    if Game.room_mode(room) != "truth_collapse" do
      {:error, "Invalid mode"}
    else
      round = round || room.current_round

      already =
        case :ets.lookup(:truth_results_ack, {room_id, round, player_id}) do
          [_] -> true
          [] -> false
        end

      :ets.insert(:truth_results_ack, {{room_id, round, player_id}, true})

      progress = build_progress(room_id, round)
      broadcast_progress(room.code, progress)
      maybe_auto_advance(room_id, round, progress)

      {:ok,
       %{
         received: true,
         already_ready: already,
         distortion_note: nil,
         progress: progress
       }}
    end
  end

  def build_progress(room_id, round) do
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

    %{
      round: round,
      acked_count: length(acked_ids),
      total: length(connected),
      acked_player_ids: acked_ids
    }
  end

  def broadcast_progress(room_code, progress) do
    Endpoint.broadcast("game:#{room_code}", "truth_results_progress", progress)
    Endpoint.broadcast("display:#{room_code}", "display:truth_results_progress", progress)
  end

  @ready_advance_grace_ms 3_000

  defp maybe_auto_advance(room_id, round, %{acked_count: acked, total: total}) do
    if total > 0 and acked >= total do
      key = {:ready_auto_advance_scheduled, room_id, round}

      case :ets.insert_new(:round_scored, {key, true}) do
        true ->
          spawn(fn ->
            Process.sleep(@ready_advance_grace_ms)
            PubSub.broadcast(VnParty.PubSub, "room:#{room_id}:internal", {:auto_advance_round, room_id, round})
          end)

        false ->
          :ok
      end
    end
  end
end
