defmodule Agora.Media.Audio.Compressor do
  @moduledoc """
  Feedforward, linked-stereo, soft-knee downward compressor — the
  standard "decoupled" topology from Giannoulis, Massberg & Reiss,
  *Digital Dynamic Range Compressor Design: A Tutorial and Analysis*
  (J. Audio Eng. Soc., 2012): an instantaneous per-sample static curve
  computes the *target* gain reduction from the current peak level, and
  a separate `EnvelopeFollower` smooths the actually-applied reduction
  toward that target using the user's attack/release times. Smoothing
  the gain-reduction signal (rather than the input level before the
  curve) is what makes `attack_ms`/`release_ms` mean what a broadcaster
  expects: how fast the compressor reacts, not how fast it listens.

  Soft knee (`knee_db`): below `threshold - knee/2` no reduction is
  applied; above `threshold + knee/2` it's the plain `ratio`; in between,
  a quadratic blends the two so there's no audible "elbow" at threshold.
  """

  alias Agora.Media.Audio.{DB, EnvelopeFollower}

  defstruct [:threshold_db, :ratio, :knee_db, :makeup_gain_db, :follower]

  @type t :: %__MODULE__{
          threshold_db: float,
          ratio: float,
          knee_db: float,
          makeup_gain_db: float,
          follower: EnvelopeFollower.t()
        }

  @spec new(map(), pos_integer()) :: t()
  def new(params, sample_rate \\ 48_000) do
    %__MODULE__{
      threshold_db: params.threshold_db,
      ratio: params.ratio,
      knee_db: params.knee_db,
      makeup_gain_db: params.makeup_gain_db,
      follower: EnvelopeFollower.new(params.attack_ms, params.release_ms, sample_rate)
    }
  end

  @spec update_params(t(), map(), pos_integer()) :: t()
  def update_params(%__MODULE__{} = state, params, sample_rate \\ 48_000) do
    %{
      state
      | threshold_db: params.threshold_db,
        ratio: params.ratio,
        knee_db: params.knee_db,
        makeup_gain_db: params.makeup_gain_db,
        follower:
          EnvelopeFollower.set_times(
            state.follower,
            params.attack_ms,
            params.release_ms,
            sample_rate
          )
    }
  end

  @spec process(t(), {float(), float()}) :: {t(), {float(), float()}}
  def process(%__MODULE__{} = state, {l, r}) do
    level_db = DB.linear_to_db(max(abs(l), abs(r)))
    target_reduction_db = static_curve(level_db, state.threshold_db, state.ratio, state.knee_db)

    follower = EnvelopeFollower.update(state.follower, target_reduction_db)
    gain = DB.db_to_linear(state.makeup_gain_db - follower.envelope)

    {%{state | follower: follower}, {l * gain, r * gain}}
  end

  @doc """
  The static gain-reduction curve (dB of reduction, always >= 0) for a
  given instantaneous level, threshold, ratio, and knee width. Exposed
  and tested on its own since it's the part that determines *how much*
  compression happens; `process/2` layers ballistics on top of it.
  """
  @spec static_curve(number(), number(), number(), number()) :: float()
  def static_curve(level_db, threshold_db, ratio, knee_db) do
    knee_start = threshold_db - knee_db / 2
    knee_end = threshold_db + knee_db / 2

    cond do
      knee_db > 0 and level_db > knee_start and level_db < knee_end ->
        over = level_db - knee_start
        (1 / ratio - 1) * over * over / (2 * knee_db) * -1

      level_db >= knee_end ->
        (level_db - threshold_db) * (1 - 1 / ratio)

      true ->
        0.0
    end
  end
end
