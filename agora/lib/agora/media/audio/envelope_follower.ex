defmodule Agora.Media.Audio.EnvelopeFollower do
  @moduledoc """
  One-pole follower with independent attack/release time constants —
  the shared "ballistics" primitive behind `NoiseGate`, `Compressor`, and
  `Limiter`. All three are structurally the same thing: track some
  non-negative scalar over time, smoothing increases with `attack_ms` and
  decreases with `release_ms`; they differ only in *what* scalar they
  track (signal level for the gate, gain reduction for the compressor and
  limiter) and what they do with the result.

  Standard one-pole ballistics: `coeff = exp(-1 / (time_s * sample_rate))`,
  `envelope = coeff * envelope + (1 - coeff) * target`.
  """

  defstruct attack_coeff: 0.0, release_coeff: 0.0, envelope: 0.0

  @type t :: %__MODULE__{attack_coeff: float, release_coeff: float, envelope: float}

  @spec new(attack_ms :: number, release_ms :: number, sample_rate :: pos_integer) :: t
  def new(attack_ms, release_ms, sample_rate) do
    %__MODULE__{
      attack_coeff: time_coeff(attack_ms, sample_rate),
      release_coeff: time_coeff(release_ms, sample_rate)
    }
  end

  @spec set_times(t(), attack_ms :: number, release_ms :: number, sample_rate :: pos_integer) :: t
  def set_times(%__MODULE__{} = state, attack_ms, release_ms, sample_rate) do
    %{
      state
      | attack_coeff: time_coeff(attack_ms, sample_rate),
        release_coeff: time_coeff(release_ms, sample_rate)
    }
  end

  @doc """
  Moves the envelope one step toward `target` (a non-negative scalar,
  already in whatever domain the caller wants — linear amplitude or dB).
  Uses the attack coefficient when the envelope is rising toward the
  target, release when falling.
  """
  @spec update(t(), number()) :: t()
  def update(%__MODULE__{envelope: envelope} = state, target) do
    coeff = if target > envelope, do: state.attack_coeff, else: state.release_coeff
    %{state | envelope: coeff * envelope + (1.0 - coeff) * target}
  end

  defp time_coeff(time_ms, _sample_rate) when time_ms <= 0, do: 0.0

  defp time_coeff(time_ms, sample_rate) do
    :math.exp(-1.0 / (time_ms / 1000.0 * sample_rate))
  end
end
