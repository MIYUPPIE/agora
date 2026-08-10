defmodule Agora.Media.Audio.NoiseGate do
  @moduledoc """
  Linked-stereo (both channels gated together, so the signal never
  swings off-center) downward gate/expander: attenuates by `range_db`
  (not full silence — a hard mute reads as a jarring on/off click and
  swallows room tone; a floor a broadcaster can still dial down to -90dB
  gives them that option without it being the only option) whenever the
  signal peak drops below `threshold_db` for longer than `hold_ms`.

  `attack_ms`/`release_ms` shape how fast the *applied gain* opens and
  closes, not how fast the level is measured — level detection is
  instantaneous (peak of the current sample) on purpose, so the gate
  reacts to the true attack of incoming speech instead of smearing it.
  """

  alias Agora.Media.Audio.{DB, EnvelopeFollower}

  defstruct [:threshold_lin, :range_db, :follower, :hold_samples, hold_counter: 0]

  @type t :: %__MODULE__{
          threshold_lin: float,
          range_db: float,
          follower: EnvelopeFollower.t(),
          hold_samples: non_neg_integer,
          hold_counter: non_neg_integer
        }

  @spec new(map(), pos_integer()) :: t()
  def new(params, sample_rate) do
    %__MODULE__{
      threshold_lin: DB.db_to_linear(params.threshold_db),
      range_db: params.range_db,
      follower: EnvelopeFollower.new(params.attack_ms, params.release_ms, sample_rate),
      hold_samples: DB.ms_to_samples(params.hold_ms, sample_rate)
    }
  end

  @spec update_params(t(), map(), pos_integer()) :: t()
  def update_params(%__MODULE__{} = state, params, sample_rate) do
    %{
      state
      | threshold_lin: DB.db_to_linear(params.threshold_db),
        range_db: params.range_db,
        follower:
          EnvelopeFollower.set_times(
            state.follower,
            params.attack_ms,
            params.release_ms,
            sample_rate
          ),
        hold_samples: DB.ms_to_samples(params.hold_ms, sample_rate)
    }
  end

  @spec process(t(), {float(), float()}) :: {t(), {float(), float()}}
  def process(%__MODULE__{} = state, {l, r}) do
    peak = max(abs(l), abs(r))

    {target_gain_db, hold_counter} =
      cond do
        peak >= state.threshold_lin -> {0.0, state.hold_samples}
        state.hold_counter > 0 -> {0.0, state.hold_counter - 1}
        true -> {state.range_db, 0}
      end

    follower = EnvelopeFollower.update(state.follower, target_gain_db)
    gain = DB.db_to_linear(follower.envelope)

    {%{state | follower: follower, hold_counter: hold_counter}, {l * gain, r * gain}}
  end
end
