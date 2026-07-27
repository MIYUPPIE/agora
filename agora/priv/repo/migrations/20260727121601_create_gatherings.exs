defmodule Agora.Repo.Migrations.CreateGatherings do
  use Ecto.Migration

  def change do
    create table(:gatherings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :status, :string, null: false, default: "scheduled"
      add :stream_key, :string, null: false
      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:gatherings, [:stream_key])
    create index(:gatherings, [:user_id])
  end
end
