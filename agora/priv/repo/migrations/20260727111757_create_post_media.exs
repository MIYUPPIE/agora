defmodule Agora.Repo.Migrations.CreatePostMedia do
  use Ecto.Migration

  def change do
    create table(:post_media, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :url, :string, null: false
      add :position, :integer, null: false, default: 0
      add :byte_size, :integer

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:post_media, [:post_id])
  end
end
