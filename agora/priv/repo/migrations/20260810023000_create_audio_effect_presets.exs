defmodule Agora.Repo.Migrations.CreateAudioEffectPresets do
  use Ecto.Migration

  def change do
    create table(:audio_effect_presets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :params, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:audio_effect_presets, [:user_id])
  end
end
