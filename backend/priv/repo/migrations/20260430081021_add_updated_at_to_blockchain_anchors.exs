defmodule VnParty.Repo.Migrations.AddUpdatedAtToBlockchainAnchors do
  use Ecto.Migration

  def change do
    alter table(:blockchain_anchors) do
      add_if_not_exists :updated_at, :utc_datetime
    end
  end
end
