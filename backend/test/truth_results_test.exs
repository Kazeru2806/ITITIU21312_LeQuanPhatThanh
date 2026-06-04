defmodule VnParty.TruthResultsTest do
  use ExUnit.Case, async: false

  alias VnParty.Game
  alias VnParty.TruthResults
  alias VnParty.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "record_results_ready is idempotent and broadcasts progress" do
    {:ok, room} = Game.create_room(%{"mode" => "truth_collapse", "total_rounds" => 3})
    {:ok, p1} = Game.join_room(room.code, "alice")
    {:ok, p2} = Game.join_room(room.code, "bob")
    {:ok, _} = Game.join_room(room.code, "carol")
    {:ok, room} = Game.start_game(room.id)

    :ets.insert(:truth_room_phase, {room.id, %{round: room.current_round, phase: "results"}})

    assert {:ok, %{already_ready: false, progress: %{acked_count: 1}}} =
             TruthResults.record_results_ready(room.id, p1.id, room.current_round)

    assert {:ok, %{already_ready: true, progress: %{acked_count: 1}}} =
             TruthResults.record_results_ready(room.id, p1.id, room.current_round)

    assert {:ok, %{progress: %{acked_count: 2, total: total}}} =
             TruthResults.record_results_ready(room.id, p2.id, room.current_round)

    assert total >= 3
  end
end
