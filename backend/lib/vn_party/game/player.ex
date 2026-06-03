defmodule VnParty.Game.Player do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "players" do
    field :nickname, :string
    field :avatar, :string
    field :score, :integer, default: 0
    field :connected, :boolean, default: true
    field :is_host, :boolean, default: false
    field :joined_at, :utc_datetime
    field :last_seen_at, :utc_datetime

    belongs_to :room, VnParty.Game.Room
    has_many :events, VnParty.Game.Event
    has_many :answer_commits, VnParty.Game.AnswerCommit

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new player
  """
  def changeset(player, attrs) do
    player
    |> cast(attrs, [:nickname, :avatar, :score, :connected, :is_host, :room_id, :joined_at, :last_seen_at])
    |> validate_required([:nickname, :room_id])
    |> validate_length(:nickname, min: 2, max: 20)
    |> validate_format(:nickname, ~r/^[a-zA-Z0-9_\-\p{L}]+$/u, message: "must contain only letters, numbers, underscores, and hyphens")
    |> unique_constraint([:room_id, :nickname])
  end

  @doc """
  Updates player score
  """
  def update_score_changeset(player, points) do
    new_score = max(0, player.score + points)
    player
    |> cast(%{score: new_score}, [:score])
  end

  @doc """
  Updates connection status
  """
  def update_connection_changeset(player, connected) do
    player
    |> cast(%{connected: connected, last_seen_at: DateTime.utc_now()}, [:connected, :last_seen_at])
  end

  @doc """
  Marks player as host
  """
  def make_host_changeset(player) do
    player
    |> cast(%{is_host: true}, [:is_host])
  end
end