defmodule Agora.Media.Audio.Transcriber do
  @moduledoc """
  Membrane filter that live-captions a Gathering — a pure passthrough
  (every buffer it receives goes straight to `:output` unchanged, same
  shape and sample rate it came in with) that *also* feeds a copy of
  every buffer's bytes into `Agora.Media.Audio.UtteranceBuffer`, and
  whenever that produces a complete utterance, hands it off to
  `Agora.Media.Audio.WhisperClient` on a supervised, unlinked `Task` —
  never inline in this process.

  That's not an optimization, it's a correctness requirement: this
  element sits between `:effects` and `:aac_encoder` in
  `Agora.Media.GatheringPipeline` (see its moduledoc), directly on the
  audio's path to the HLS packager. A live gathering must never stall
  waiting on an HTTP round-trip to whisper-server — captions are a
  bonus, not something worth even a few hundred ms of extra broadcast
  latency for every listener. Task failures (whisper-server down,
  request timeout) are swallowed for the same reason: no captions beats
  no broadcast, exactly the same call `browser_broadcast.js` makes for
  each client-side DSP stage and `Agora.Media.Audio.WhisperServer` makes
  for the server process itself.

  Position in the chain (after `:effects`, before `:aac_encoder`) is
  deliberate: transcribing the noise-gated, leveled audio the effects
  chain already produces measurably beats transcribing the raw signal —
  the same clean-up a broadcaster dials in for listeners' ears also
  helps Whisper.
  """

  use Membrane.Filter
  require Logger

  alias Agora.Media.Audio.{UtteranceBuffer, WhisperClient, WhisperServer}
  alias Agora.Transcripts
  alias Membrane.RawAudio

  @sample_rate 48_000
  @channels 2
  @stream_format %RawAudio{sample_format: :s16le, sample_rate: @sample_rate, channels: @channels}

  def_input_pad(:input, accepted_format: %RawAudio{sample_format: :s16le}, flow_control: :auto)
  def_output_pad(:output, accepted_format: %RawAudio{sample_format: :s16le}, flow_control: :auto)

  def_options(
    gathering_id: [spec: String.t(), description: "Gathering these captions are appended to."],
    enabled: [
      spec: boolean(),
      default: true,
      description: "Whether live captioning is on. Toggled live via {:set_enabled, bool}."
    ]
  )

  @impl true
  def handle_init(_ctx, opts) do
    {[],
     %{
       gathering_id: opts.gathering_id,
       enabled: opts.enabled,
       buffer: UtteranceBuffer.new(@sample_rate),
       elapsed_ms: 0
     }}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, @stream_format}], state}
  end

  @impl true
  def handle_stream_format(:input, _stream_format, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    {[buffer: {:output, buffer}], process(buffer.payload, state)}
  end

  @impl true
  def handle_parent_notification({:set_enabled, enabled?}, _ctx, state)
      when is_boolean(enabled?) do
    {[], %{state | enabled: enabled?}}
  end

  def handle_parent_notification(_other, _ctx, state), do: {[], state}

  defp process(payload, %{enabled: false} = state) do
    %{state | elapsed_ms: state.elapsed_ms + chunk_duration_ms(payload)}
  end

  defp process(payload, state) do
    elapsed_ms = state.elapsed_ms + chunk_duration_ms(payload)

    case UtteranceBuffer.push(state.buffer, payload) do
      {buffer, nil} ->
        %{state | buffer: buffer, elapsed_ms: elapsed_ms}

      {buffer, %{audio: audio, duration_ms: duration_ms}} ->
        start_ms = max(round(elapsed_ms - duration_ms), 0)
        spawn_transcription(state.gathering_id, audio, start_ms, round(elapsed_ms))
        %{state | buffer: buffer, elapsed_ms: elapsed_ms}
    end
  end

  defp chunk_duration_ms(payload) do
    frames = byte_size(payload) / (@channels * 2)
    frames / @sample_rate * 1000
  end

  defp spawn_transcription(gathering_id, pcm, start_ms, end_ms) do
    if WhisperServer.available?() do
      Task.Supervisor.start_child(Agora.TaskSupervisor, fn ->
        case WhisperClient.transcribe(pcm) do
          {:ok, text} when is_binary(text) ->
            Transcripts.append_live_segment!(gathering_id, %{
              text: text,
              start_ms: start_ms,
              end_ms: end_ms
            })

          {:ok, nil} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "Agora.Media.Audio.Transcriber: transcription failed for gathering " <>
                "#{gathering_id}: #{inspect(reason)}"
            )
        end
      end)
    end
  end
end
