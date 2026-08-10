defmodule Agora.Media.Audio.DB do
  @moduledoc """
  Decibel <-> linear amplitude conversions shared by every DSP stage.
  0 dBFS corresponds to a linear amplitude of 1.0 throughout the effects
  chain, which runs entirely in normalized float samples (see `Agora.Media.Audio.PCM`).
  """

  # -144 dB is below the noise floor of a 24-bit signal and comfortably
  # below anything a 16-bit PCM stream can represent — used as a safe
  # stand-in for "silence" so log10(0) never produces -infinity/NaN.
  @silence_db -144.0

  @spec db_to_linear(number()) :: float()
  def db_to_linear(db) when is_number(db), do: :math.pow(10, db / 20)

  @spec linear_to_db(number()) :: float()
  def linear_to_db(linear) when is_number(linear) and linear > 0, do: 20 * :math.log10(linear)
  def linear_to_db(linear) when is_number(linear), do: @silence_db

  @doc "Converts a duration in milliseconds to a non-negative integer sample count at `sample_rate`."
  @spec ms_to_samples(number(), pos_integer()) :: non_neg_integer()
  def ms_to_samples(ms, sample_rate), do: max(0, round(ms / 1000.0 * sample_rate))
end
