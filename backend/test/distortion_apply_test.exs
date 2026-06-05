defmodule VnParty.DistortionApplyTest do
  use ExUnit.Case, async: false

  alias VnParty.{FakeInject, TruthDistortionApply}

  defp base_question do
    %{
      id: "q1",
      category: "general",
      correct: "B",
      options: [
        %{id: "A", text: "3"},
        %{id: "B", text: "5"},
        %{id: "C", text: "6"},
        %{id: "D", text: "7"}
      ]
    }
  end

  defp stub_swap(_room_id, _round, category, _mode) do
    base_question()
    |> Map.put(:category, category)
    |> Map.put(:text, "Swapped #{category}")
  end

  defp apply_opts(extra \\ []) do
    [
      swap_fn: &stub_swap/4,
      category_picker: &stub_pick/2,
      di_fn: fn _ -> 10 end,
      connected_player_ids: ["p1", "p2", "p3"]
    ] ++ extra
  end

  defp stub_pick(_question, _requested), do: "history"

  setup do
    room_id = Ecto.UUID.generate()
    round = 2

    on_exit(fn ->
      :ets.match_delete(:truth_distortions, {room_id, :_, :_, :_, :_})
    end)

    {:ok, room_id: room_id, round: round}
  end

  test "swap_category changes theme and question category", %{room_id: room_id, round: round} do
    :ets.insert(:truth_distortions, {room_id, round, "p1", "swap_category", %{}})

    {q, effects} =
      TruthDistortionApply.apply_for_round(room_id, round, base_question(), apply_opts())

    assert q.category == "history"
    assert effects.category_timeline == ["general", "history"]
    assert Enum.any?(effects.log, &(&1.action == "swap_category"))
  end

  test "force_blind targets a player for shuffle", %{room_id: room_id, round: round} do
    :ets.insert(:truth_distortions, {room_id, round, "p1", "force_blind", %{"target_player_id" => "p2"}})

    {_q, effects} =
      TruthDistortionApply.apply_for_round(room_id, round, base_question(), apply_opts())

    assert MapSet.member?(effects.blind_targets, "p2")
  end

  test "inject_fake_option replaces option text on host question", %{room_id: room_id, round: round} do
    :ets.insert(:truth_distortions, {room_id, round, "p1", "inject_fake_option", %{"fake_text" => "5"}})

    {q, effects} =
      TruthDistortionApply.apply_for_round(room_id, round, base_question(), apply_opts())

    assert Enum.find(q.options, &(&1.id == "B")).text == "5"
    assert effects.injected_option_ids == ["B"]
    assert length(effects.fake_entries) == 1
  end

  test "inject victim selection attributes matching option letter for fool scoring" do
    q = %{
      correct: "B",
      options: [
        %{id: "A", text: "3"},
        %{id: "B", text: "5"},
        %{id: "C", text: "6"},
        %{id: "D", text: "7"}
      ]
    }

    victim = FakeInject.pick_victim(q, "5")
    assert victim.id == "B"

    replaced =
      Enum.map(q.options, fn o ->
        if o.id == victim.id, do: %{o | text: "5"}, else: o
      end)

    assert Enum.find(replaced, &(&1.id == "B")).text == "5"
  end

  test "remove_option adds per-player remove_targets when players exist", %{room_id: room_id, round: round} do
    :ets.insert(:truth_distortions, {room_id, round, "p1", "remove_option", %{"target_player_id" => "p2"}})

    {q, effects} =
      TruthDistortionApply.apply_for_round(room_id, round, base_question(), apply_opts())

    assert effects.remove_count == 1
    assert Map.has_key?(effects.remove_targets, "p2")
    assert length(effects.remove_targets["p2"]) == 1
    refute "B" in effects.remove_targets["p2"]
    assert length(q.options) == 4
    assert Enum.any?(effects.log, &(&1.action == "remove_option" and &1.target_player_id == "p2"))
  end

  test "multiple remove_option on same target stacks wrong options but keeps correct", %{room_id: room_id, round: round} do
    :ets.insert(:truth_distortions, {room_id, round, "p1", "remove_option", %{"target_player_id" => "p2"}})
    :ets.insert(:truth_distortions, {room_id, round, "p3", "remove_option", %{"target_player_id" => "p2"}})
    :ets.insert(:truth_distortions, {room_id, round, "p4", "remove_option", %{"target_player_id" => "p2"}})

    {_q, effects} =
      TruthDistortionApply.apply_for_round(room_id, round, base_question(), apply_opts())

    removed = effects.remove_targets["p2"]
    assert length(removed) == 3
    refute "B" in removed
    assert Enum.all?(removed, &(&1 in ["A", "C", "D"]))
  end
end
