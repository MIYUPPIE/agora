defmodule Agora.Media.AudioEffectPreset do
  @moduledoc """
  A broadcaster's saved live-audio-effects settings — one row per user.
  Loaded as the starting point whenever their next Gathering goes live,
  and updated in place every time they tweak a slider while broadcasting
  (see `Agora.Media.AudioEffects`), so the whole gain/EQ/compressor/gate/
  reverb/limiter chain "remembers" how they like to sound between
  Gatherings instead of resetting to factory defaults every time.

  `params` is stored as-is from `Agora.Media.Audio.Params` (a plain,
  already-range-clamped nested map) — validation happens once, at the
  `Agora.Media.Audio.Params.clamp/1` boundary before it ever reaches a
  changeset, not duplicated here as Ecto field-level validations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "audio_effect_presets" do
    belongs_to :user, Agora.Accounts.User
    field :params, :map

    timestamps(type: :utc_datetime)
  end

  def changeset(preset, attrs) do
    preset
    |> cast(attrs, [:user_id, :params])
    |> validate_required([:user_id, :params])
    |> unique_constraint(:user_id)
  end
end
