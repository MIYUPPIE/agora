defmodule Agora.Repo.Migrations.CreatePostMedia do
  use Ecto.Migration

  def change do
    create table(:post_media) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :url, :string, null: false
      add :position, :integer, null: false, default: 0
      add :byte_size, :integer

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:post_media, [:post_id])
  end
end
