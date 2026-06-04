defmodule VnParty.H3WsCommitTest do
  @moduledoc """
  Layer B — commit–reveal checks through the same secure API the channel uses.
  Complements h3_attack_sim_test.exs (white-box) for thesis methodology.
  """
  use ExUnit.Case, async: false

  alias VnParty.Game
  alias VnParty.Game.AnswerCommit
  alias VnParty.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp setup_round! do
    {:ok, room} = Game.create_room(%{"mode" => "classic", "total_rounds" => 5})
    {:ok, player} = Game.join_room(room.code, "ws_player_#{System.unique_integer([:positive])}")
    {:ok, room} = Game.start_game(room.id)
    Game.record_commit_window(room.id, room.current_round, 15)
    {room, player}
  end

  test "replay commit hash is rejected (same path as WebSocket commit_answer)" do
    {room, player} = setup_round!()
    round = room.current_round
    salt = AnswerCommit.generate_salt()
    hash = AnswerCommit.generate_commit_hash("A", salt)

    assert {:ok, _} =
             Game.commit_answer_secure(room.id, player.id, round, "q#{round}", hash)

    assert {:error, :replay_attack} =
             Game.commit_answer_secure(room.id, player.id, round, "q#{round}", hash)
  end

  test "late commit after window closed is rejected" do
    {room, player} = setup_round!()
    round = room.current_round
    past = System.system_time(:millisecond) - 60_000
    Game.put_commit_window(room.id, round, past, 1)

    salt = AnswerCommit.generate_salt()
    hash = AnswerCommit.generate_commit_hash("A", salt)

    assert {:error, :late_commit} =
             Game.commit_answer_secure(room.id, player.id, round, "q#{round}", hash)
  end

  test "hash tampering is detected on reveal path" do
    {room, player} = setup_round!()
    round = room.current_round
    commit = insert_commit!(room, player, round, "A")

    {:ok, tampered} =
      commit
      |> Ecto.Changeset.change(%{answer: "B"})
      |> Repo.update()

    {:ok, flagged} = Game.flag_hash_tampering_if_any(tampered)
    assert flagged.is_valid == false
    assert flagged.violation_reason == "hash_tampering"
  end

  defp insert_commit!(room, player, round, answer) do
    salt = AnswerCommit.generate_salt()
    hash = AnswerCommit.generate_commit_hash(answer, salt)

    {:ok, commit} =
      Game.commit_answer_secure(room.id, player.id, round, "q#{round}", hash)

    {:ok, commit} =
      commit
      |> Ecto.Changeset.change(%{answer: answer, salt: salt, is_valid: true})
      |> Repo.update()

    commit
  end
end
