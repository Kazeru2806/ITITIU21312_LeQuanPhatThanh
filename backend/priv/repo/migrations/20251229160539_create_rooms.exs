defmodule VnParty.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :host_id, :binary_id
      add :state, :string, null: false, default: "lobby"
      add :config, :map, default: %{}
      add :current_round, :integer, default: 0
      add :total_rounds, :integer, default: 5
      add :max_players, :integer, default: 8
      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:rooms, [:code])
    create index(:rooms, [:state])
    create index(:rooms, [:inserted_at])
  end
end