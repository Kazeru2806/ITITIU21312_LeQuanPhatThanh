defmodule VnParty.Repo.Migrations.CreateGameSnapshots do
  use Ecto.Migration

  def change do
    create table(:game_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false
      add :seq, :bigint, null: false
      add :round, :integer, null: false
      add :state, :string, null: false
      add :scores, :map, default: %{}
      add :active_players, {:array, :binary_id}, default: []
      add :game_data, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:game_snapshots, [:room_id, :seq])
    create index(:game_snapshots, [:inserted_at])
  end
end