defmodule Agora.Media.Audio.AACDecoder do
  @moduledoc """
  Decodes ADTS-framed AAC into raw s16le stereo PCM at 48kHz, via a
  long-running `ffmpeg -f aac -i pipe:0 -f s16le ... pipe:1` subprocess.
  See `Agora.Media.Audio.FFmpegPort` for why ffmpeg rather than a native
  Membrane AAC decoder plugin.

  Input buffers (each one already a complete ADTS frame, as produced by
  the upstream `Membrane.AAC.Parser`) are written to ffmpeg's stdin as
  they arrive; decoded PCM bytes arrive asynchronously on stdout and are
  forwarded downstream the moment they're read. There is no 1:1
  relationship between input and output buffer boundaries — ffmpeg
  reframes internally — which is exactly what `flow_control: :auto` on
  both pads is for: this element doesn't drive demand itself, Membrane's
  automatic flow control keeps input pulled and output paced against
  whatever's actually demanded downstream.

  ## Shutdown

  A vanilla Erlang `Port` can't half-close a subprocess's stdin (signal
  EOF) while continuing to read its stdout — `Port.close/1` tears down
  both directions together. Closing the port the *instant* upstream
  reaches `end_of_stream` raced ffmpeg's own flushing: ffmpeg was often
  still mid-write of already-decoded output when the read side vanished
  underneath it (confirmed against a real run — ffmpeg logged "Error
  submitting a packet to the muxer: Broken pipe"), silently truncating
  audio, not just the "last few ms" a closing-immediately design might
  assume. Instead, `handle_end_of_stream/3` waits `@flush_grace_period_ms`
  before closing, giving ffmpeg real wall-clock time to finish decoding
  whatever was already written to its stdin — audio decode runs many
  times faster than realtime, so this bounds worst-case shutdown latency
  without truncating anything a broadcaster actually said.
  """

  use Membrane.Filter
  require Logger

  alias Agora.Media.Audio.FFmpegPort
  alias Membrane.{AAC, RawAudio}

  @sample_rate 48_000
  @channels 2
  @stream_format %RawAudio{sample_format: :s16le, sample_rate: @sample_rate, channels: @channels}
  @flush_grace_period_ms 500

  def_input_pad(:input, accepted_format: %AAC{encapsulation: :ADTS}, flow_control: :auto)
  def_output_pad(:output, accepted_format: %RawAudio{sample_format: :s16le}, flow_control: :auto)

  @impl true
  def handle_init(_ctx, _opts), do: {[], %{port: nil}}

  @impl true
  def handle_setup(_ctx, state) do
    # -probesize/-analyzeduration: ffmpeg's default stream probing on a
    # raw ADTS pipe waits for ~16KB (roughly a second of audio) before
    # it finishes analyzing the stream and starts emitting *any* decoded
    # output — confirmed empirically (a live loopback test sat at 0 bytes
    # of output for a solid second despite continuously-arriving valid
    # input). Since our AAC config is already fully known (48kHz stereo,
    # fixed by this whole pipeline), there's nothing to probe for; these
    # flags tell ffmpeg to skip that phase and start decoding from the
    # first frame it can parse. -flush_packets keeps it from batching
    # decoded output either.
    args =
      ~w(-probesize 32 -analyzeduration 0 -f aac -i pipe:0
         -f s16le -acodec pcm_s16le -ar #{@sample_rate} -ac #{@channels} -flush_packets 1 pipe:1)

    {[], %{state | port: FFmpegPort.open(args)}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, @stream_format}], state}
  end

  @impl true
  def handle_stream_format(:input, _input_format, _ctx, state) do
    # The default Filter behaviour broadcasts the *input* format to
    # :output — wrong here, since :input is AAC and :output is RawAudio.
    # The real (and only) output format was already sent from
    # handle_playing/2 and never changes.
    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    FFmpegPort.write(state.port, buffer.payload)
    {[], state}
  end

  @impl true
  def handle_info({port, {:data, data}}, _ctx, %{port: port} = state) do
    {[buffer: {:output, %Membrane.Buffer{payload: data}}], state}
  end

  def handle_info({port, {:exit_status, 0}}, _ctx, %{port: port} = state) do
    {[end_of_stream: :output], %{state | port: nil}}
  end

  def handle_info({port, {:exit_status, status}}, _ctx, %{port: port} = _state) do
    Logger.error("Agora.Media.Audio.AACDecoder: ffmpeg exited with status #{status}")
    raise "ffmpeg AAC decoder exited unexpectedly with status #{status}"
  end

  def handle_info(:close_after_flush, _ctx, %{port: nil} = state), do: {[], state}

  def handle_info(:close_after_flush, _ctx, state) do
    FFmpegPort.close(state.port)
    {[end_of_stream: :output], %{state | port: nil}}
  end

  # Catches late/stray port messages after the port has already been
  # closed and state.port set to nil (e.g. a {:data, ...} message queued
  # right before shutdown) — safe to drop rather than crash on.
  def handle_info(_other, _ctx, state), do: {[], state}

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    Process.send_after(self(), :close_after_flush, @flush_grace_period_ms)
    {[], state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    FFmpegPort.close(state.port)
    {[terminate: :normal], %{state | port: nil}}
  end
end
