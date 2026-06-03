defmodule VnParty.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  def change do
    create table(:players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false
      add :nickname, :string, null: false
      add :avatar, :string
      add :score, :integer, default: 0
      add :connected, :boolean, default: true
      add :is_host, :boolean, default: false
      add :joined_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:players, [:room_id])
    create index(:players, [:connected])
    create unique_index(:players, [:room_id, :nickname])
  end
end