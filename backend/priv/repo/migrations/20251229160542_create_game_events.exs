defmodule VnParty.Repo.Migrations.CreateGameEvents do
  use Ecto.Migration

  def change do
    create table(:game_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false
      add :player_id, references(:players, type: :binary_id, on_delete: :nilify_all)
      add :event_type, :string, null: false
      add :seq, :bigint, null: false
      add :payload, :map, default: %{}
      add :metadata, :map, default: %{}
      
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:game_events, [:room_id, :seq])
    create index(:game_events, [:event_type])
    # Removed the duplicate line that was here
  end
end