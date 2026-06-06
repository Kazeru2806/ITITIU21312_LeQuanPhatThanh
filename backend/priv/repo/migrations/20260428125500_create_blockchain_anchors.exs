defmodule VnParty.Repo.Migrations.CreateBlockchainAnchors do
  use Ecto.Migration

  def change do
    create table(:blockchain_anchors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false
      add :event_id, references(:game_events, type: :binary_id, on_delete: :delete_all), null: false
      add :seq, :bigint, null: false
      add :event_hash, :string, null: false
      add :prev_chain_hash, :string
      add :chain_hash, :string, null: false
      add :tx_hash, :string
      add :status, :string, null: false, default: "pending"
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:blockchain_anchors, [:room_id, :seq])
    create index(:blockchain_anchors, [:status])
    create unique_index(:blockchain_anchors, [:event_id])
  end
end
