defmodule VnParty.Game.Snapshot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game_snapshots" do
    field :seq, :integer
    field :round, :integer
    field :state, :string
    field :scores, :map, default: %{}
    field :active_players, {:array, :binary_id}, default: []
    field :game_data, :map, default: %{}

    belongs_to :room, VnParty.Game.Room

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Creates a changeset for a new snapshot
  """
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:room_id, :seq, :round, :state, :scores, :active_players, :game_data])
    |> validate_required([:room_id, :seq, :round, :state])
  end

  @doc """
  Creates a snapshot from current game state
  """
  def create_snapshot(room, players, current_seq) do
    scores = 
      players
      |> Enum.map(fn player -> {player.id, player.score} end)
      |> Map.new()

    active_players = 
      players
      |> Enum.filter(& &1.connected)
      |> Enum.map(& &1.id)

    %__MODULE__{}
    |> changeset(%{
      room_id: room.id,
      seq: current_seq,
      round: room.current_round,
      state: room.state,
      scores: scores,
      active_players: active_players,
      game_data: %{
        total_rounds: room.total_rounds,
        started_at: room.started_at
      }
    })
  end
end