defmodule Agora.Media.Transcription do
  @moduledoc """
  Live-toggling captions for a running Gathering — the transcription
  analogue of `Agora.Media.AudioEffects.update_params/3`'s live-pipeline
  push, minus the persisted-preset half (whether captions are on isn't
  something worth remembering across Gatherings the way effects
  settings are; it just defaults on every time — see
  `Agora.Media.Audio.Transcriber`'s `enabled` option default).
  """

  @doc """
  Toggles live captioning for `gathering_id`'s running pipeline, if it
  has one right now. A no-op (not an error) when the Gathering isn't
  live — mirrors `Agora.Media.AudioEffects.push_to_live_pipeline/2`.
  """
  @spec set_enabled(Ecto.UUID.t(), boolean()) :: :ok | :not_live
  def set_enabled(gathering_id, enabled?) when is_boolean(enabled?) do
    case Registry.lookup(Agora.Media.GatheringRegistry, gathering_id) do
      [{pid, _}] ->
        Membrane.Pipeline.call(pid, {:set_transcription_enabled, enabled?})
        :ok

      [] ->
        :not_live
    end
  end
end
