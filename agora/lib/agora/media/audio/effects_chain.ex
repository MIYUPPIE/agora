defmodule Agora.Media.Audio.EffectsChain do
  @moduledoc """
  The full stateful real-time audio effects chain — the single entry
  point `Agora.Media.Audio.EffectsFilter` calls once per Membrane buffer.
  Operates on interleaved s16le stereo PCM in, s16le stereo PCM out.

  Chain order: Noise Gate -> 4-band EQ -> Compressor -> Reverb -> Limiter.

  This follows the livestream processing order from the guide this
  feature was built from, with one deliberate change: Reverb moves
  *before* the Limiter instead of after it. A limiter's job is to
  guarantee nothing downstream ever clips; putting anything — including
  an "optional" reverb tail — after the last gain stage defeats that
  guarantee for exactly the peaks the reverb itself adds. Gate -> EQ ->
  Compressor -> Reverb -> Limiter keeps the limiter as the true last line
  of defense, which is what "hard peak protection" is supposed to mean.
  """

  alias Agora.Media.Audio.{Biquad, Compressor, Limiter, NoiseGate, Params, PCM, Reverb}

  @sample_rate 48_000

  defstruct [:params, :gate, :eq, :compressor, :reverb, :limiter]

  @type t :: %__MODULE__{
          params: Params.t(),
          gate: NoiseGate.t(),
          eq: map(),
          compressor: Compressor.t(),
          reverb: Reverb.t(),
          limiter: Limiter.t()
        }

  @spec sample_rate() :: pos_integer()
  def sample_rate, do: @sample_rate

  @spec new(Params.t()) :: t()
  def new(params \\ Params.default()) do
    params = Params.clamp(params)

    %__MODULE__{
      params: params,
      gate: NoiseGate.new(params.noise_gate, @sample_rate),
      eq: build_eq(params.eq),
      compressor: Compressor.new(params.compressor, @sample_rate),
      reverb: Reverb.new(params.reverb, @sample_rate),
      limiter: Limiter.new(params.limiter, @sample_rate)
    }
  end

  @doc """
  Applies a partial parameter change (already-validated or not — it goes
  through `Params.merge/2`, which clamps). Every stage's *coefficients*
  are rebuilt from the new params, but each stage's running memory
  (filter delay lines, envelope followers, reverb tank) is preserved —
  that's what keeps a live slider move a smooth transition instead of an
  audible restart click.
  """
  @spec update_params(t(), map()) :: t()
  def update_params(%__MODULE__{} = chain, changes) do
    new_params = Params.merge(chain.params, changes)

    %{
      chain
      | params: new_params,
        gate: NoiseGate.update_params(chain.gate, new_params.noise_gate, @sample_rate),
        eq: update_eq(chain.eq, new_params.eq),
        compressor:
          Compressor.update_params(chain.compressor, new_params.compressor, @sample_rate),
        reverb: Reverb.update_params(chain.reverb, new_params.reverb, @sample_rate),
        limiter: Limiter.update_params(chain.limiter, new_params.limiter, @sample_rate)
    }
  end

  @doc "Processes one interleaved s16le stereo PCM buffer through the whole chain, returning `{new_chain, pcm_binary}`."
  @spec process_buffer(t(), binary()) :: {t(), binary()}
  def process_buffer(%__MODULE__{} = chain, pcm_binary) when is_binary(pcm_binary) do
    input_gain = Agora.Media.Audio.DB.db_to_linear(chain.params.input_gain_db)
    frames = PCM.decode_stereo(pcm_binary)

    {out_frames, chain} =
      Enum.map_reduce(frames, chain, fn {l, r}, chain ->
        process_frame(chain, {l * input_gain, r * input_gain})
      end)

    {chain, PCM.encode_stereo(out_frames)}
  end

  defp process_frame(chain, frame) do
    {gate, frame} =
      if chain.params.noise_gate.enabled,
        do: NoiseGate.process(chain.gate, frame),
        else: {chain.gate, frame}

    {eq, frame} = run_eq(chain.eq, chain.params.eq, frame)

    {compressor, frame} =
      if chain.params.compressor.enabled,
        do: Compressor.process(chain.compressor, frame),
        else: {chain.compressor, frame}

    {reverb, frame} =
      if chain.params.reverb.enabled,
        do: Reverb.process(chain.reverb, frame),
        else: {chain.reverb, frame}

    {limiter, frame} =
      if chain.params.limiter.enabled,
        do: Limiter.process(chain.limiter, frame),
        else: {chain.limiter, frame}

    {frame,
     %{chain | gate: gate, eq: eq, compressor: compressor, reverb: reverb, limiter: limiter}}
  end

  # ── EQ: 4 independent bands, each stereo (independent L/R filter memory) ─

  defp build_eq(eq_params) do
    %{
      highpass:
        new_band(Biquad.highpass(eq_params.highpass.freq, eq_params.highpass.q, @sample_rate)),
      low_shelf:
        new_band(
          Biquad.low_shelf(eq_params.low_shelf.freq, eq_params.low_shelf.gain_db, @sample_rate)
        ),
      mid_peak:
        new_band(
          Biquad.peaking(
            eq_params.mid_peak.freq,
            eq_params.mid_peak.gain_db,
            eq_params.mid_peak.q,
            @sample_rate
          )
        ),
      high_shelf:
        new_band(
          Biquad.high_shelf(eq_params.high_shelf.freq, eq_params.high_shelf.gain_db, @sample_rate)
        )
    }
  end

  defp new_band(coeffs),
    do: %{coeffs: coeffs, left: Biquad.new_state(), right: Biquad.new_state()}

  defp update_eq(eq, eq_params) do
    %{
      highpass: %{
        eq.highpass
        | coeffs: Biquad.highpass(eq_params.highpass.freq, eq_params.highpass.q, @sample_rate)
      },
      low_shelf: %{
        eq.low_shelf
        | coeffs:
            Biquad.low_shelf(eq_params.low_shelf.freq, eq_params.low_shelf.gain_db, @sample_rate)
      },
      mid_peak: %{
        eq.mid_peak
        | coeffs:
            Biquad.peaking(
              eq_params.mid_peak.freq,
              eq_params.mid_peak.gain_db,
              eq_params.mid_peak.q,
              @sample_rate
            )
      },
      high_shelf: %{
        eq.high_shelf
        | coeffs:
            Biquad.high_shelf(
              eq_params.high_shelf.freq,
              eq_params.high_shelf.gain_db,
              @sample_rate
            )
      }
    }
  end

  defp run_eq(eq, eq_params, {l, r}) do
    {highpass, l, r} = run_band(eq.highpass, eq_params.highpass.enabled, l, r)
    {low_shelf, l, r} = run_band(eq.low_shelf, eq_params.low_shelf.enabled, l, r)
    {mid_peak, l, r} = run_band(eq.mid_peak, eq_params.mid_peak.enabled, l, r)
    {high_shelf, l, r} = run_band(eq.high_shelf, eq_params.high_shelf.enabled, l, r)

    {%{highpass: highpass, low_shelf: low_shelf, mid_peak: mid_peak, high_shelf: high_shelf},
     {l, r}}
  end

  defp run_band(band, true, l, r) do
    {out_l, left} = Biquad.process(band.coeffs, band.left, l)
    {out_r, right} = Biquad.process(band.coeffs, band.right, r)
    {%{band | left: left, right: right}, out_l, out_r}
  end

  defp run_band(band, false, l, r), do: {band, l, r}
end
