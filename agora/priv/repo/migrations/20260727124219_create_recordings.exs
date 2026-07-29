defmodule Agora.Repo.Migrations.CreateRecordings do
  use Ecto.Migration

  def change do
    create table(:recordings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :gathering_id, references(:gatherings, type: :binary_id, on_delete: :delete_all),
        null: false

      add :start_seq, :integer, null: false
      add :end_seq, :integer
      add :status, :string, null: false, default: "recording"
      add :download_url, :string
      add :byte_size, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:recordings, [:user_id, :gathering_id])
  end
end
