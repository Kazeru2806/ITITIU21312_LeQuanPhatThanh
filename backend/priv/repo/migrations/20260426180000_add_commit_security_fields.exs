defmodule VnParty.Repo.Migrations.AddCommitSecurityFields do
  use Ecto.Migration

  def change do
    alter table(:answer_commits) do
      add :commit_delay_ms, :integer
      add :violation_reason, :string
    end

    create index(:answer_commits, [:violation_reason])
  end
end

