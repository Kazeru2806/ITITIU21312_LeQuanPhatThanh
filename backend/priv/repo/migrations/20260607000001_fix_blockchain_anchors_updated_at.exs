defmodule VnParty.Repo.Migrations.FixBlockchainAnchorsUpdatedAt do
  use Ecto.Migration

  def change do
    # Drop the wrongly named "true" column and ensure updated_at exists
    alter table(:blockchain_anchors) do
      remove_if_exists :true, :utc_datetime
      add_if_not_exists :updated_at, :utc_datetime
    end
  end
end
