defmodule Agora.Media.Audio.AACEncoder do
  @moduledoc """
  Encodes raw s16le stereo PCM at 48kHz into ADTS-framed AAC, via a
  long-running `ffmpeg -f s16le ... -i pipe:0 -c:a aac -f adts pipe:1`
  subprocess. See `Agora.Media.Audio.FFmpegPort` for why ffmpeg rather
  than a native Membrane AAC encoder plugin.

  Emits its output as an untyped `Membrane.RemoteStream` of raw bytes
  rather than a fully-formed `%Membrane.AAC{}` — the bytes arriving on
  ffmpeg's stdout are chunked by the OS pipe, not by AAC frame boundary,
  so this element genuinely doesn't know where one ADTS frame ends and
  the next begins. That's not a gap: it's exactly the job the downstream
  `Membrane.AAC.Parser` already does for the *original*, un-processed
  RTMP source (which itself hands the parser an untyped `RemoteStream`)
  — re-using that same parser after this encoder keeps both audio paths
  (through the effects chain, and — before this feature existed —
  straight from RTMP) synchronizing AAC frames the same way.

  ## Startup latency

  Measured empirically against a live loopback: ffmpeg's AAC encoder +
  ADTS muxer, fed over a pipe, does not emit its first output packet
  until roughly ~1.5-2 seconds of PCM has been written to it — this
  held across every combination of `-fflags nobuffer`, `-flags
  low_delay`, `-flush_packets 1`, and reduced `-probesize` tried (probing
  isn't the cause here the way it was for `Agora.Media.Audio.AACDecoder`;
  this looks like inherent encoder/muxer buffering that isn't exposed as
  a configurable flag). Once primed, output tracks input continuously —
  this is a one-time startup cost at the beginning of a Gathering, not a
  per-buffer latency. Given `Agora.Media.GatheringPipeline`'s own HLS
  packaging already carries an ~8-12s end-to-end latency floor by design
  (see its moduledoc), an extra ~2s before the very first segment is
  encodable is within the system's existing latency budget, not a new
  class of problem — documented here rather than "fixed" because there
  isn't a known flag that fixes it.

  ## Shutdown

  See `Agora.Media.Audio.AACDecoder`'s moduledoc — same reasoning,
  mirrored: closing the port the instant upstream reaches
  `end_of_stream` raced ffmpeg's own flush, so `handle_end_of_stream/3`
  waits `@flush_grace_period_ms` before closing instead.
  """

  use Membrane.Filter
  require Logger

  alias Agora.Media.Audio.FFmpegPort
  alias Membrane.{RawAudio, RemoteStream}

  @sample_rate 48_000
  @channels 2
  @stream_format %RemoteStream{content_format: Membrane.AAC, type: :bytestream}
  # Comfortably above the ~1.5-2s startup priming latency documented
  # above — a Gathering that ends before the encoder ever primed still
  # needs this long to flush whatever's queued inside ffmpeg.
  @flush_grace_period_ms 3_000

  def_input_pad(:input, accepted_format: %RawAudio{sample_format: :s16le}, flow_control: :auto)
  def_output_pad(:output, accepted_format: %RemoteStream{type: :bytestream}, flow_control: :auto)

  def_options(
    bitrate: [
      spec: pos_integer(),
      default: 128_000,
      description: "Target AAC encode bitrate in bits/sec."
    ]
  )

  @impl true
  def handle_init(_ctx, opts), do: {[], %{port: nil, bitrate: opts.bitrate}}

  @impl true
  def handle_setup(_ctx, state) do
    args =
      ~w(-f s16le -ar #{@sample_rate} -ac #{@channels} -i pipe:0
         -c:a aac -b:a #{state.bitrate} -f adts -flush_packets 1 pipe:1)

    {[], %{state | port: FFmpegPort.open(args)}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, @stream_format}], state}
  end

  @impl true
  def handle_stream_format(:input, _input_format, _ctx, state) do
    # See Agora.Media.Audio.AACDecoder.handle_stream_format/4 — same
    # reasoning, mirrored: :input is RawAudio, :output is RemoteStream.
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
    Logger.error("Agora.Media.Audio.AACEncoder: ffmpeg exited with status #{status}")
    raise "ffmpeg AAC encoder exited unexpectedly with status #{status}"
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
