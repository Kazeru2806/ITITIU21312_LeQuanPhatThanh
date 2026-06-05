defmodule VnParty.TruthDistortionUseTest do
  use ExUnit.Case, async: false

  alias VnParty.Game
  alias VnParty.TruthDistortionUse
  alias VnParty.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "remove_option applies during results phase and stores distortion" do
    {:ok, room} = Game.create_room(%{"mode" => "truth_collapse", "total_rounds" => 3})
    {:ok, p1} = Game.join_room(room.code, "alice")
    {:ok, p2} = Game.join_room(room.code, "bob")
    {:ok, room} = Game.start_game(room.id)

    :ets.insert(:truth_room_phase, {room.id, %{round: room.current_round, phase: "results"}})
    :ets.insert(:truth_player_stats, {p1.id, %{tp: 0, di: 0, ps: 0, charges: 10}})

    assert {:ok, %{used: true, remaining_charges: 8}} =
             TruthDistortionUse.apply(
               room.id,
               p1.id,
               "alice",
               "remove_option",
               %{"action" => "remove_option", "target_player_id" => p2.id}
             )

    effect_round = room.current_round + 1

    assert Enum.any?(:ets.lookup(:truth_distortions, room.id), fn
             {rid, round, pid, "remove_option", payload} ->
               rid == room.id and round == effect_round and pid == p1.id and
                 payload["target_player_id"] == p2.id

             _ ->
               false
           end)
  end
end
