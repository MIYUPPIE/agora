defmodule Agora.Media.Audio.Reverb do
  @moduledoc """
  Light Schroeder/Freeverb-style reverb send: 4 parallel damped comb
  filters summed together, feeding 2 series allpass filters, mixed with
  the dry signal by `mix`. This is the classic Freeverb architecture
  (Jezar's public-domain design, ubiquitous in open-source reverbs)
  trimmed from its usual 8 combs down to 4 — appropriate for a *light*
  broadcast reverb send rather than a lush musical hall, and cheaper to
  run per-sample in pure Elixir.

  Deliberate simplification: the reverb tank runs on the mono sum of
  L+R and is mixed back into both channels equally, rather than running
  fully independent stereo tanks with per-channel-offset tunings (what
  "real" Freeverb does for stereo width). For a light voice/talk send
  this is inaudible in practice and halves the per-sample cost; a wide
  musical reverb would need the full stereo tank, which is out of scope
  for "gentle broadcast polish."

  Comb feedback comes from `room_size` (higher = longer, more resonant
  tail); the one-pole lowpass in each comb's feedback path comes from
  `damping` (higher = darker, faster-decaying tail) — both are exactly
  Freeverb's own parameter mapping.
  """

  # Freeverb's tunings, in samples at 44100Hz; scaled to the runtime
  # sample rate in new/2. Using the first 4 of Freeverb's 8 combs and
  # both of its allpasses.
  @comb_tunings_44100 [1116, 1188, 1277, 1356]
  @allpass_tunings_44100 [556, 441]
  @allpass_feedback 0.5

  defmodule Comb do
    @moduledoc false
    defstruct [:queue, :feedback, :damp1, :damp2, filter_store: 0.0]

    @type t :: %__MODULE__{
            queue: :queue.queue(),
            feedback: float,
            damp1: float,
            damp2: float,
            filter_store: float
          }

    def new(length, feedback, damping) do
      %__MODULE__{queue: fill(length), feedback: feedback, damp1: damping, damp2: 1.0 - damping}
    end

    defp fill(length), do: Enum.reduce(1..length, :queue.new(), fn _i, q -> :queue.in(0.0, q) end)

    def process(%__MODULE__{} = c, input) do
      {{:value, output}, queue} = :queue.out(c.queue)
      filter_store = output * c.damp2 + c.filter_store * c.damp1
      queue = :queue.in(input + filter_store * c.feedback, queue)
      {output, %{c | queue: queue, filter_store: filter_store}}
    end
  end

  defmodule Allpass do
    @moduledoc false
    defstruct [:queue, :feedback]

    @type t :: %__MODULE__{queue: :queue.queue(), feedback: float}

    def new(length, feedback), do: %__MODULE__{queue: fill(length), feedback: feedback}

    defp fill(length), do: Enum.reduce(1..length, :queue.new(), fn _i, q -> :queue.in(0.0, q) end)

    def process(%__MODULE__{} = a, input) do
      {{:value, delayed}, queue} = :queue.out(a.queue)
      output = -input + delayed
      queue = :queue.in(input + delayed * a.feedback, queue)
      {output, %{a | queue: queue}}
    end
  end

  defstruct [:mix, :combs, :allpasses]

  @type t :: %__MODULE__{mix: float, combs: [Comb.t()], allpasses: [Allpass.t()]}

  @spec new(map(), pos_integer()) :: t()
  def new(params, sample_rate) do
    scale = sample_rate / 44_100
    feedback = room_size_to_feedback(params.room_size)

    combs =
      Enum.map(@comb_tunings_44100, fn len ->
        Comb.new(round(len * scale), feedback, params.damping)
      end)

    allpasses =
      Enum.map(@allpass_tunings_44100, fn len ->
        Allpass.new(round(len * scale), @allpass_feedback)
      end)

    %__MODULE__{mix: params.mix, combs: combs, allpasses: allpasses}
  end

  @spec update_params(t(), map(), pos_integer()) :: t()
  def update_params(%__MODULE__{} = state, params, _sample_rate) do
    feedback = room_size_to_feedback(params.room_size)

    combs =
      Enum.map(state.combs, fn c ->
        %{c | feedback: feedback, damp1: params.damping, damp2: 1.0 - params.damping}
      end)

    %{state | mix: params.mix, combs: combs}
  end

  @spec process(t(), {float(), float()}) :: {t(), {float(), float()}}
  def process(%__MODULE__{} = state, {l, r}) do
    mono_in = (l + r) / 2

    {combs, comb_sum} =
      Enum.map_reduce(state.combs, 0.0, fn comb, acc ->
        {out, comb} = Comb.process(comb, mono_in)
        {comb, acc + out}
      end)

    comb_avg = comb_sum / length(state.combs)

    {allpasses, wet} =
      Enum.map_reduce(state.allpasses, comb_avg, fn allpass, signal ->
        {out, allpass} = Allpass.process(allpass, signal)
        {allpass, out}
      end)

    out_l = l * (1.0 - state.mix) + wet * state.mix
    out_r = r * (1.0 - state.mix) + wet * state.mix

    {%{state | combs: combs, allpasses: allpasses}, {out_l, out_r}}
  end

  # Freeverb's own room_size -> feedback mapping, clamped short of 1.0
  # for guaranteed stability (feedback >= 1.0 would make the comb
  # filters diverge instead of decay).
  defp room_size_to_feedback(room_size) do
    (room_size * 0.28 + 0.7) |> min(0.98) |> max(0.0)
  end
end
