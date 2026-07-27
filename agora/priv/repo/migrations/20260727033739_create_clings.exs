defmodule Agora.Repo.Migrations.CreateClings do
  use Ecto.Migration

  def change do
    create table(:clings) do
      add :clinger_id, references(:users, on_delete: :delete_all), null: false
      add :clinged_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:clings, [:clinger_id, :clinged_id])
    create index(:clings, [:clinged_id])

    create constraint(:clings, :clinger_is_not_clinged, check: "clinger_id <> clinged_id")
  end
end
