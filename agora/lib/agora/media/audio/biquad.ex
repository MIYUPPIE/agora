defmodule Agora.Media.Audio.Biquad do
  @moduledoc """
  Second-order IIR (biquad) filter: coefficient design using the RBJ Audio
  EQ Cookbook formulas (the same formulas the Web Audio API's
  `BiquadFilterNode` is specified against), plus Direct Form I processing.

  Coefficients (`t/0`) and per-channel filter memory (`state/0`) are kept
  separate on purpose: `Agora.Media.Audio.EffectsChain` recomputes
  coefficients whenever a broadcaster moves an EQ slider, but always
  keeps the running `x1/x2/y1/y2` memory from before the change — that's
  what makes a live parameter tweak a smooth transition instead of an
  audible click (the alternative, resetting filter memory on every
  change, restarts the impulse response from zero each time).
  """

  alias __MODULE__

  defstruct b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0

  @type t :: %__MODULE__{b0: float, b1: float, b2: float, a1: float, a2: float}

  defmodule State do
    @moduledoc "Per-channel filter memory (previous two inputs/outputs) for a `Biquad`."
    defstruct x1: 0.0, x2: 0.0, y1: 0.0, y2: 0.0
    @type t :: %__MODULE__{x1: float, x2: float, y1: float, y2: float}
  end

  @spec new_state() :: State.t()
  def new_state, do: %State{}

  @doc "Processes a single sample through the filter, returning `{output, new_state}`."
  @spec process(t(), State.t(), float()) :: {float(), State.t()}
  def process(%__MODULE__{} = c, %State{} = s, x) do
    y = c.b0 * x + c.b1 * s.x1 + c.b2 * s.x2 - c.a1 * s.y1 - c.a2 * s.y2
    {y, %State{x1: x, x2: s.x1, y1: y, y2: s.y1}}
  end

  @doc "A neutral (identity) filter — used when a band is disabled but its slot still needs coefficients."
  @spec identity() :: t()
  def identity, do: %__MODULE__{b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0}

  @doc "2nd-order high-pass (Butterworth-shaped via Q), -3dB at `freq`."
  @spec highpass(number(), number(), pos_integer()) :: t()
  def highpass(freq, q, sample_rate) do
    {w0, cos_w0, alpha} = trig(freq, q, sample_rate)

    b0 = (1 + cos_w0) / 2
    b1 = -(1 + cos_w0)
    b2 = (1 + cos_w0) / 2
    a0 = 1 + alpha
    a1 = -2 * cos_w0
    a2 = 1 - alpha

    normalize(b0, b1, b2, a0, a1, a2, w0)
  end

  @doc "2nd-order low-pass, -3dB at `freq`."
  @spec lowpass(number(), number(), pos_integer()) :: t()
  def lowpass(freq, q, sample_rate) do
    {w0, cos_w0, alpha} = trig(freq, q, sample_rate)

    b0 = (1 - cos_w0) / 2
    b1 = 1 - cos_w0
    b2 = (1 - cos_w0) / 2
    a0 = 1 + alpha
    a1 = -2 * cos_w0
    a2 = 1 - alpha

    normalize(b0, b1, b2, a0, a1, a2, w0)
  end

  @doc "Peaking (bell) EQ band: boosts/cuts `gain_db` around `freq` with bandwidth set by `q`."
  @spec peaking(number(), number(), number(), pos_integer()) :: t()
  def peaking(freq, gain_db, q, sample_rate) do
    {w0, cos_w0, alpha} = trig(freq, q, sample_rate)
    a = :math.pow(10, gain_db / 40)

    b0 = 1 + alpha * a
    b1 = -2 * cos_w0
    b2 = 1 - alpha * a
    a0 = 1 + alpha / a
    a1 = -2 * cos_w0
    a2 = 1 - alpha / a

    normalize(b0, b1, b2, a0, a1, a2, w0)
  end

  @doc "Low shelf: boosts/cuts `gain_db` below `freq`."
  @spec low_shelf(number(), number(), pos_integer()) :: t()
  def low_shelf(freq, gain_db, sample_rate) do
    {w0, cos_w0, sin_w0} = freq_trig(freq, sample_rate)
    a = :math.pow(10, gain_db / 40)
    sqrt_a = :math.sqrt(a)
    alpha = shelf_alpha(sin_w0)
    two_sqrt_a_alpha = 2 * sqrt_a * alpha

    b0 = a * (a + 1 - (a - 1) * cos_w0 + two_sqrt_a_alpha)
    b1 = 2 * a * (a - 1 - (a + 1) * cos_w0)
    b2 = a * (a + 1 - (a - 1) * cos_w0 - two_sqrt_a_alpha)
    a0 = a + 1 + (a - 1) * cos_w0 + two_sqrt_a_alpha
    a1 = -2 * (a - 1 + (a + 1) * cos_w0)
    a2 = a + 1 + (a - 1) * cos_w0 - two_sqrt_a_alpha

    normalize(b0, b1, b2, a0, a1, a2, w0)
  end

  @doc "High shelf: boosts/cuts `gain_db` above `freq`."
  @spec high_shelf(number(), number(), pos_integer()) :: t()
  def high_shelf(freq, gain_db, sample_rate) do
    {w0, cos_w0, sin_w0} = freq_trig(freq, sample_rate)
    a = :math.pow(10, gain_db / 40)
    sqrt_a = :math.sqrt(a)
    alpha = shelf_alpha(sin_w0)
    two_sqrt_a_alpha = 2 * sqrt_a * alpha

    b0 = a * (a + 1 + (a - 1) * cos_w0 + two_sqrt_a_alpha)
    b1 = -2 * a * (a - 1 + (a + 1) * cos_w0)
    b2 = a * (a + 1 + (a - 1) * cos_w0 - two_sqrt_a_alpha)
    a0 = a + 1 - (a - 1) * cos_w0 + two_sqrt_a_alpha
    a1 = 2 * (a - 1 - (a + 1) * cos_w0)
    a2 = a + 1 - (a - 1) * cos_w0 - two_sqrt_a_alpha

    normalize(b0, b1, b2, a0, a1, a2, w0)
  end

  @doc """
  Magnitude of the filter's frequency response at `freq`, computed
  directly from the coefficients in the z-domain — evaluated at
  `z = e^(j*2*pi*freq/sample_rate)`. This is a second, independent way of
  deriving the filter's behavior (frequency-domain, closed-form) from the
  exact same coefficients `process/3` uses in the time domain, so it's a
  genuine correctness check on `process/3` rather than a restatement of it.

  Only used by tests and any future "show me the EQ curve" UI — never on
  the real-time audio path.
  """
  @spec magnitude_response(t(), number(), pos_integer()) :: float()
  def magnitude_response(%__MODULE__{} = c, freq, sample_rate) do
    w = 2 * :math.pi() * freq / sample_rate
    cos_w = :math.cos(w)
    sin_w = :math.sin(w)
    cos_2w = :math.cos(2 * w)
    sin_2w = :math.sin(2 * w)

    num_re = c.b0 + c.b1 * cos_w + c.b2 * cos_2w
    num_im = -c.b1 * sin_w - c.b2 * sin_2w
    den_re = 1 + c.a1 * cos_w + c.a2 * cos_2w
    den_im = -c.a1 * sin_w - c.a2 * sin_2w

    :math.sqrt(num_re * num_re + num_im * num_im) /
      :math.sqrt(den_re * den_re + den_im * den_im)
  end

  # ── Internal ──────────────────────────────────────────────────────────

  defp trig(freq, q, sample_rate) do
    w0 = 2 * :math.pi() * freq / sample_rate
    cos_w0 = :math.cos(w0)
    alpha = :math.sin(w0) / (2 * q)
    {w0, cos_w0, alpha}
  end

  defp freq_trig(freq, sample_rate) do
    w0 = 2 * :math.pi() * freq / sample_rate
    {w0, :math.cos(w0), :math.sin(w0)}
  end

  # RBJ cookbook: alpha = sin(w0)/2 * sqrt((A + 1/A)*(1/S - 1) + 2), where
  # S is the shelf "slope". Shelf filters here use a fixed S = 1 (the
  # cookbook's steepest-without-overshoot default, and how most broadcast
  # EQs present shelf bands: just frequency + gain, no separate slope
  # knob) — at S = 1, (1/S - 1) is exactly 0, which cancels the A-term
  # entirely, so alpha reduces to sin(w0) * sqrt(2)/2 regardless of gain.
  defp shelf_alpha(sin_w0), do: sin_w0 * :math.sqrt(2) / 2

  defp normalize(b0, b1, b2, a0, a1, a2, _w0) do
    %Biquad{b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0}
  end
end
