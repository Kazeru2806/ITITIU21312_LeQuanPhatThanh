defmodule VnParty.Game.AnswerCommit do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "answer_commits" do
    field :round, :integer
    field :question_id, :string
    field :commit_hash, :string
    field :answer, :string
    field :salt, :string
    field :committed_at, :utc_datetime
    field :revealed_at, :utc_datetime
    field :is_valid, :boolean
    field :is_correct, :boolean
    field :points_awarded, :integer, default: 0
    field :commit_delay_ms, :integer
    field :violation_reason, :string

    belongs_to :room, VnParty.Game.Room
    belongs_to :player, VnParty.Game.Player

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for committing an answer
  """
  def commit_changeset(answer_commit, attrs) do
    answer_commit
    |> cast(attrs, [:room_id, :player_id, :round, :question_id, :commit_hash, :committed_at])
    |> validate_required([:room_id, :player_id, :round, :question_id, :commit_hash, :committed_at])
    |> unique_constraint([:room_id, :player_id, :round])
  end

  @doc """
  Creates a changeset for revealing an answer
  """
  def reveal_changeset(answer_commit, attrs) do
    answer_commit
    |> cast(attrs, [:answer, :salt, :revealed_at, :is_valid])
    |> validate_required([:answer, :salt, :revealed_at])
    |> validate_commit_hash()
  end

  @doc """
  Creates a changeset for scoring
  """
  def score_changeset(answer_commit, is_correct, points) do
    answer_commit
    |> cast(%{is_correct: is_correct, points_awarded: points}, [:is_correct, :points_awarded])
  end

  @doc """
  Generates a commit hash from answer and salt
  """
  def generate_commit_hash(answer, salt) do
    :crypto.hash(:sha256, "#{answer}:#{salt}")
    |> Base.encode16(case: :lower)
  end

  @doc """
  Generates a random salt
  """
  def generate_salt do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  # Private function to validate commit hash matches
  defp validate_commit_hash(changeset) do
    answer = get_change(changeset, :answer)
    salt = get_change(changeset, :salt)
    stored_hash = get_field(changeset, :commit_hash)

    if answer && salt && stored_hash do
      computed_hash = generate_commit_hash(answer, salt)
      
      if computed_hash == stored_hash do
        put_change(changeset, :is_valid, true)
      else
        changeset
        |> put_change(:is_valid, false)
        |> add_error(:answer, "commit hash does not match")
      end
    else
      changeset
    end
  end
end