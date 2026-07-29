defmodule Agora.Repo.Migrations.CreateComments do
  use Ecto.Migration

  def change do
    create table(:comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:comments, [:post_id])
  end
end
