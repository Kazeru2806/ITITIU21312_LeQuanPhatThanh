defmodule VnParty.Repo.Migrations.CreateAnswerCommits do
  use Ecto.Migration

  def change do
    create table(:answer_commits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false
      add :player_id, references(:players, type: :binary_id, on_delete: :delete_all), null: false
      add :round, :integer, null: false
      add :question_id, :string, null: false
      add :commit_hash, :string, null: false
      add :answer, :string
      add :salt, :string
      add :committed_at, :utc_datetime, null: false
      add :revealed_at, :utc_datetime
      add :is_valid, :boolean
      add :is_correct, :boolean
      add :points_awarded, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:answer_commits, [:room_id, :round])
    create index(:answer_commits, [:player_id])
    create unique_index(:answer_commits, [:room_id, :player_id, :round])
  end
end