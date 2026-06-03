defmodule VnParty.Game.Room do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_states ~w(lobby round_start answering commit_locked revealing scoring round_end game_end)

  schema "rooms" do
    field :code, :string
    field :state, :string, default: "lobby"
    field :config, :map, default: %{}
    field :current_round, :integer, default: 0
    field :total_rounds, :integer, default: 5
    field :max_players, :integer, default: 8
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    field :host_id, :binary_id
    has_many :players, VnParty.Game.Player
    has_many :events, VnParty.Game.Event
    has_many :snapshots, VnParty.Game.Snapshot

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new room
  """
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:code, :state, :config, :current_round, :total_rounds, :max_players, :host_id, :started_at, :ended_at])
    |> validate_required([:code, :state])
    |> validate_inclusion(:state, @valid_states)
    |> validate_number(:max_players, greater_than: 1, less_than_or_equal_to: 20)
    |> validate_number(:total_rounds, greater_than: 0, less_than_or_equal_to: 20)
    |> unique_constraint(:code)
  end

  @doc """
  Generates a unique 6-character room code
  """
  def generate_code do
    :crypto.strong_rand_bytes(3)
    |> Base.encode16()
    |> binary_part(0, 6)
  end

  @doc """
  Updates the room state
  """
  def update_state_changeset(room, new_state) do
    room
    |> cast(%{state: new_state}, [:state])
    |> validate_inclusion(:state, @valid_states)
  end

  @doc """
  Advances to the next round
  """
  def advance_round_changeset(room) do
    room
    |> cast(%{current_round: room.current_round + 1}, [:current_round])
    |> validate_number(:current_round, less_than_or_equal_to: room.total_rounds)
  end
end