defmodule VnParty.DistortionApplyTest do
  use ExUnit.Case, async: false

  alias VnParty.FakeInject

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
end
