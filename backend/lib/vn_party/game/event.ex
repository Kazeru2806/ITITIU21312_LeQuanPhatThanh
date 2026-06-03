defmodule VnParty.Game.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_types ~w(
    room_created player_joined player_left
    game_started round_started question_revealed
    answer_committed answer_revealed
    scoring_completed round_ended game_ended
    player_reconnected player_disconnected
  )

  schema "game_events" do
    field :event_type, :string
    field :seq, :integer
    field :payload, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :room, VnParty.Game.Room
    belongs_to :player, VnParty.Game.Player

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Creates a changeset for a new event
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_type, :seq, :payload, :metadata, :room_id, :player_id])
    |> validate_required([:event_type, :seq, :room_id])
    |> validate_inclusion(:event_type, @event_types)
    |> unique_constraint([:room_id, :seq])
  end

  @doc """
  Creates a new event with auto-incrementing sequence number
  """
  def create_event(room_id, event_type, payload, player_id \\ nil, metadata \\ %{}) do
    %__MODULE__{}
    |> changeset(%{
      room_id: room_id,
      player_id: player_id,
      event_type: event_type,
      seq: get_next_seq(room_id),
      payload: payload,
      metadata: Map.merge(metadata, %{
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      })
    })
  end

  defp get_next_seq(_room_id) do
    # This will be implemented properly in the context module
    # For now, return a timestamp-based placeholder
    System.system_time(:millisecond)
  end
end