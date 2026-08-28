defmodule Agora.Media.Audio.UtteranceBuffer do
  @moduledoc """
  Pure, stateful energy-gated endpointer: decides *when* a run of PCM
  buffers constitutes one spoken utterance worth sending to Whisper,
  rather than transcribing on a fixed timer.

  Why not just transcribe every fixed N-second window: cutting on a
  clock cuts mid-word/mid-sentence at the boundary, which measurably
  hurts Whisper's accuracy (it has no idea the audio was truncated
  mid-thought) and doubles as the #1 cause of the classic
  whisper.cpp-on-silence hallucination (short, mostly-silent windows are
  exactly what produces spurious "Thank you." transcripts — confirmed
  hands-on against a real base.en model: 2s of true digital silence
  reliably transcribes to `"Thank you.\\n"`). Segmenting on natural
  pauses instead means every chunk handed to Whisper is a real,
  complete utterance, and — combined with the energy gate in
  `push/2` never even calling Whisper on a chunk with no speech in it at
  all — starves that hallucination mode at the source rather than
  filtering it after the fact.

  Flush triggers, whichever comes first:

    * Trailing silence reaches `silence_hangover_ms` after at least
      `min_utterance_ms` of actual speech — the normal case, flushing
      right after a broadcaster finishes a sentence/thought.
    * Total buffered duration reaches `max_utterance_ms` regardless of
      silence — bounds worst-case latency and memory for a broadcaster
      who talks continuously without pausing.

  A silence run that closes out *too little* speech (a cough, a click,
  a stray "um") is discarded without ever being flushed — see the
  `speech_ms < min_utterance_ms` branch of `push/2` — so the caller
  never spends a Whisper call on it.

  Only `push/2` is stateful (a struct threaded through by the caller,
  `Agora.Media.Audio.Transcriber`); RMS/duration math is ordinary pure
  functions, same testing philosophy as `Agora.Media.Audio.EffectsChain`.
  """

  alias Agora.Media.Audio.{DB, PCM}

  # Stereo, matching every other Audio.* module in this pipeline (PCM,
  # EffectsChain, AACDecoder) — the whole chain is hardcoded to it, so
  # there's no real "channels" input to be generic over.
  @channels 2

  @enforce_keys [:sample_rate]
  defstruct sample_rate: nil,
            silence_threshold_db: -50.0,
            min_utterance_ms: 500,
            silence_hangover_ms: 700,
            max_utterance_ms: 15_000,
            audio: <<>>,
            total_ms: 0,
            speech_ms: 0,
            silence_run_ms: 0,
            has_speech?: false

  @type t :: %__MODULE__{}
  @type flush :: %{audio: binary(), duration_ms: non_neg_integer()}

  @spec new(pos_integer(), keyword()) :: t()
  def new(sample_rate, opts \\ []) do
    struct!(__MODULE__, [sample_rate: sample_rate] ++ opts)
  end

  @doc """
  Feeds one chunk of raw s16le PCM into the buffer. Returns
  `{new_state, flush_or_nil}` — a non-nil second element means this
  chunk completed an utterance (or discarded a too-short one); either
  way `new_state` has already been reset to empty in that case.
  """
  @spec push(t(), binary()) :: {t(), flush() | nil}
  def push(%__MODULE__{} = state, chunk) when is_binary(chunk) do
    if byte_size(chunk) == 0 do
      {state, nil}
    else
      silent? = rms_db(chunk) < state.silence_threshold_db

      if silent? and not state.has_speech? do
        {state, nil}
      else
        chunk_ms = chunk_duration_ms(state, chunk)

        state = %{
          state
          | audio: state.audio <> chunk,
            total_ms: state.total_ms + chunk_ms,
            has_speech?: state.has_speech? or not silent?,
            speech_ms: state.speech_ms + if(silent?, do: 0, else: chunk_ms),
            silence_run_ms: if(silent?, do: state.silence_run_ms + chunk_ms, else: 0)
        }

        maybe_flush(state)
      end
    end
  end

  defp maybe_flush(state) do
    cond do
      state.silence_run_ms >= state.silence_hangover_ms and
          state.speech_ms >= state.min_utterance_ms ->
        {reset(state), %{audio: state.audio, duration_ms: state.total_ms}}

      state.silence_run_ms >= state.silence_hangover_ms ->
        {reset(state), nil}

      state.total_ms >= state.max_utterance_ms ->
        {reset(state), %{audio: state.audio, duration_ms: state.total_ms}}

      true ->
        {state, nil}
    end
  end

  defp reset(state) do
    %{state | audio: <<>>, total_ms: 0, speech_ms: 0, silence_run_ms: 0, has_speech?: false}
  end

  defp chunk_duration_ms(state, chunk) do
    bytes_per_frame = @channels * 2
    frames = byte_size(chunk) / bytes_per_frame
    frames / state.sample_rate * 1000
  end

  defp rms_db(chunk) do
    samples = PCM.decode_stereo(chunk)

    case samples do
      [] ->
        DB.linear_to_db(0.0)

      _ ->
        {sum_sq, n} =
          Enum.reduce(samples, {0.0, 0}, fn {l, r}, {sum, n} ->
            {sum + l * l + r * r, n + 2}
          end)

        DB.linear_to_db(:math.sqrt(sum_sq / n))
    end
  end
end
