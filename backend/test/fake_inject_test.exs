defmodule VnParty.FakeInjectTest do
  use ExUnit.Case, async: true

  alias VnParty.FakeInject

  test "prefers option whose text already matches fake text (even correct answer)" do
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
  end

  test "matching text hijacks that option letter even when it is the correct answer" do
    q = %{
      correct: "B",
      options: [
        %{id: "A", text: "three"},
        %{id: "B", text: "5"},
        %{id: "C", text: "6"}
      ]
    }

    victim = FakeInject.pick_victim(q, "5")
    assert victim.id == "B"
    assert victim.text == "5"
  end

  test "falls back to a wrong option when text does not match" do
    q = %{
      correct: "B",
      options: [
        %{id: "A", text: "3"},
        %{id: "B", text: "5"},
        %{id: "C", text: "6"},
        %{id: "D", text: "7"}
      ]
    }

    victim = FakeInject.pick_victim(q, "Totally new answer")
    assert victim.id in ["A", "C", "D"]
  end
end
