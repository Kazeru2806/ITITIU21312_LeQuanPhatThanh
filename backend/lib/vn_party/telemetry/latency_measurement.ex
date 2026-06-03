defmodule VnParty.Telemetry.LatencyMeasurement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "latency_measurements" do
    field :event, :string
    field :direction, :string, default: "c2s"
    field :round, :integer
    field :mode, :string
    field :client_timestamp_ms, :integer
    field :server_received_timestamp_ms, :integer
    field :latency_ms, :integer
    field :metadata, :map, default: %{}

    belongs_to :room, VnParty.Game.Room
    belongs_to :player, VnParty.Game.Player

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(measurement, attrs) do
    measurement
    |> cast(attrs, [
      :room_id,
      :player_id,
      :event,
      :direction,
      :round,
      :mode,
      :client_timestamp_ms,
      :server_received_timestamp_ms,
      :latency_ms,
      :metadata
    ])
    |> validate_required([:room_id, :event, :direction, :server_received_timestamp_ms])
  end
end

