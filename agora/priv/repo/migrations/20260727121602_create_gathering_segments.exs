defmodule Agora.Repo.Migrations.CreateGatheringSegments do
  use Ecto.Migration

  def change do
    create table(:gathering_segments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :gathering_id, references(:gatherings, type: :binary_id, on_delete: :delete_all),
        null: false

      add :sequence, :integer, null: false
      add :filename, :string, null: false
      add :byte_size, :integer
      add :duration_ms, :integer

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:gathering_segments, [:gathering_id, :sequence])
  end
end
