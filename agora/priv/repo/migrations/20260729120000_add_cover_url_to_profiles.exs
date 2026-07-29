defmodule Agora.Repo.Migrations.AddCoverUrlToProfiles do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :cover_url, :string
    end
  end
end
