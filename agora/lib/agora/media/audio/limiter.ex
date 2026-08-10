defmodule Agora.Media.Audio.Limiter do
  @moduledoc """
  Brick-wall, linked-stereo, look-ahead peak limiter — the last stage in
  `Agora.Media.Audio.EffectsChain`, guaranteeing the broadcast never
  clips no matter what the earlier stages (gain, EQ, compressor, reverb)
  do to the signal.

  Two things work together, not one:

    1. A short (5ms) look-ahead delay line, combined with a fast-attack
       `EnvelopeFollower` tracking gain reduction computed from the
       *undelayed* incoming signal. Because the follower reacts to a
       peak before that peak reaches the delayed output, gain has
       already started ducking by the time the peak arrives — a true
       limiter, not just clipping with a warning label. This is standard
       look-ahead limiter design and is exactly what the ~8-12s of
       latency this app's HLS packaging already has room for buys us:
       5ms is nothing against that budget, so there's no reason to ship
       the cheaper, audibly-worse lookahead-free version.

    2. A hard sample-clamp to `ceiling_db` applied after the smoothed
       gain, as an absolute backstop. The smoothed limiter handles the
       normal case musically; the clamp exists so a pathological
       instantaneous transient (or the first few look-ahead-window
       samples right as a stream starts, before the follower has any
       history) can never produce a sample outside the ceiling. Belt and
       suspenders, deliberately: for a live broadcast, "never clips" is
       a correctness property, not a nice-to-have.
  """

  alias Agora.Media.Audio.{DB, EnvelopeFollower}

  @lookahead_ms 5.0

  defstruct [:ceiling_lin, :follower, :lookahead_samples, delay_queue: :queue.new()]

  @type t :: %__MODULE__{
          ceiling_lin: float,
          follower: EnvelopeFollower.t(),
          lookahead_samples: non_neg_integer,
          delay_queue: :queue.queue()
        }

  @spec new(map(), pos_integer()) :: t()
  def new(params, sample_rate) do
    %__MODULE__{
      ceiling_lin: DB.db_to_linear(params.ceiling_db),
      follower: EnvelopeFollower.new(params.attack_ms, params.release_ms, sample_rate),
      lookahead_samples: DB.ms_to_samples(@lookahead_ms, sample_rate)
    }
  end

  @spec update_params(t(), map(), pos_integer()) :: t()
  def update_params(%__MODULE__{} = state, params, sample_rate) do
    %{
      state
      | ceiling_lin: DB.db_to_linear(params.ceiling_db),
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
    peak = max(abs(l), abs(r))

    target_reduction_db =
      if peak > state.ceiling_lin do
        DB.linear_to_db(peak) - DB.linear_to_db(state.ceiling_lin)
      else
        0.0
      end

    follower = EnvelopeFollower.update(state.follower, target_reduction_db)
    gain = DB.db_to_linear(-follower.envelope)

    queue = :queue.in({l, r}, state.delay_queue)

    {{dl, dr}, queue} =
      if :queue.len(queue) > state.lookahead_samples do
        {{:value, sample}, queue} = :queue.out(queue)
        {sample, queue}
      else
        {{0.0, 0.0}, queue}
      end

    out = clamp({dl * gain, dr * gain}, state.ceiling_lin)

    {%{state | follower: follower, delay_queue: queue}, out}
  end

  defp clamp({l, r}, ceiling), do: {clamp_sample(l, ceiling), clamp_sample(r, ceiling)}
  defp clamp_sample(x, ceiling) when x > ceiling, do: ceiling
  defp clamp_sample(x, ceiling) when x < -ceiling, do: -ceiling
  defp clamp_sample(x, _ceiling), do: x
end
