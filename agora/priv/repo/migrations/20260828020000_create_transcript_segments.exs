defmodule Agora.Repo.Migrations.CreateTranscriptSegments do
  use Ecto.Migration

  def change do
    create table(:transcript_segments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :gathering_id, references(:gatherings, type: :binary_id, on_delete: :delete_all),
        null: false

      add :source, :string, null: false
      add :seq, :integer, null: false
      add :start_ms, :integer, null: false
      add :end_ms, :integer, null: false
      add :text, :text, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:transcript_segments, [:gathering_id, :source, :seq])
  end
end
