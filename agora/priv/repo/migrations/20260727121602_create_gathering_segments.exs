defmodule Agora.Repo.Migrations.CreateGatheringSegments do
  use Ecto.Migration

  def change do
    create table(:gathering_segments) do
      add :gathering_id, references(:gatherings, on_delete: :delete_all), null: false
      add :sequence, :integer, null: false
      add :filename, :string, null: false
      add :byte_size, :integer
      add :duration_ms, :integer

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:gathering_segments, [:gathering_id, :sequence])
  end
end
