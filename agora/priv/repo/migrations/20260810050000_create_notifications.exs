defmodule Agora.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :recipient_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :actor_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all)
      add :gathering_id, references(:gatherings, type: :binary_id, on_delete: :delete_all)
      add :type, :string, null: false
      add :reaction_kind, :string
      add :read_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:notifications, [:recipient_id, :inserted_at])
    create index(:notifications, [:recipient_id, :read_at])
  end
end
