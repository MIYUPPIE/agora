defmodule Agora.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :title, :string
      add :body, :text
      add :duration_ms, :integer
      add :waveform, :map

      timestamps(type: :utc_datetime)
    end

    create index(:posts, [:user_id])
  end
end
