defmodule Agora.Repo.Migrations.CreateReactions do
  use Ecto.Migration

  def change do
    create table(:reactions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :kind, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:reactions, [:user_id, :post_id, :kind])
    create index(:reactions, [:post_id, :kind])
  end
end
