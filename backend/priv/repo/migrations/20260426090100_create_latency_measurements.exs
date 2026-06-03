defmodule VnParty.Repo.Migrations.CreateLatencyMeasurements do
  use Ecto.Migration

  def change do
    create table(:latency_measurements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false
      add :player_id, references(:players, type: :binary_id, on_delete: :nilify_all)

      add :event, :string, null: false
      add :direction, :string, null: false, default: "c2s"

      add :round, :integer
      add :mode, :string

      add :client_timestamp_ms, :bigint
      add :server_received_timestamp_ms, :bigint, null: false
      add :latency_ms, :integer

      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:latency_measurements, [:room_id, :inserted_at])
    create index(:latency_measurements, [:event, :inserted_at])
    create index(:latency_measurements, [:latency_ms])
  end
end

