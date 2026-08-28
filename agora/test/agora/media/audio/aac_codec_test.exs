defmodule Agora.Media.Audio.AACCodecTest do
  @moduledoc """
  Integration tests for the ffmpeg-backed AAC<->PCM codec elements,
  using a real ffmpeg subprocess (this app already hard-requires ffmpeg
  for `Agora.Media.BrowserBroadcastBridge` and `Agora.MediaFixtures`, so
  assuming it's on PATH here matches the rest of the test suite).
  """

  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Agora.Media.Audio.{AACDecoder, AACEncoder, EffectsFilter, Params, PCM}
  alias Membrane.{AAC, RawAudio, RemoteStream}
  alias Membrane.Testing

  @sample_rate 48_000

  # Generates real ADTS AAC bytes for a pure sine tone via ffmpeg's own
  # encoder (independent of AACEncoder — this is the "known good"
  # reference input the tests decode/round-trip against).
  defp synth_adts!(freq, seconds) do
    path =
      Path.join(
        System.tmp_dir!(),
        "agora-aac-codec-test-#{System.unique_integer([:positive])}.adts"
      )

    {_out, 0} =
      System.cmd("ffmpeg", [
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "lavfi",
        "-i",
        "sine=frequency=#{freq}:duration=#{seconds}:sample_rate=#{@sample_rate}",
        "-ac",
        "2",
        "-c:a",
        "aac",
        "-f",
        "adts",
        "-y",
        path
      ])

    bytes = File.read!(path)
    File.rm!(path)
    bytes
  end

  # Goertzel single-bin DFT magnitude — verifies decoded PCM actually
  # contains energy at the expected tone frequency, independent of (and
  # a cross-check on) every other assertion in this file.
  defp goertzel_magnitude(samples, target_freq, sample_rate) do
    n = length(samples)
    k = round(n * target_freq / sample_rate)
    omega = 2 * :math.pi() * k / n
    coeff = 2 * :math.cos(omega)

    {s1, s2} =
      Enum.reduce(samples, {0.0, 0.0}, fn x, {s1, s2} ->
        {x + coeff * s1 - s2, s1}
      end)

    :math.sqrt(max(s1 * s1 + s2 * s2 - coeff * s1 * s2, 0.0))
  end

  defp chunk_binary(binary, chunk_size) do
    for <<chunk::binary-size(chunk_size) <- binary>>, do: chunk
  end

  describe "AACDecoder" do
    test "decodes real ADTS AAC into 48kHz s16le stereo PCM with the expected tone frequency dominant" do
      adts = synth_adts!(1000.0, 0.5)
      chunks = chunk_binary(adts, 4096)

      spec =
        child(:source, %Testing.Source{
          output: Enum.map(chunks, &%Membrane.Buffer{payload: &1}),
          stream_format: %AAC{sample_rate: @sample_rate, channels: 2, encapsulation: :ADTS}
        })
        |> child(:decoder, AACDecoder)
        |> child(:sink, Testing.Sink)

      pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

      assert_sink_stream_format(pipeline, :sink, %RawAudio{
        sample_format: :s16le,
        sample_rate: 48_000,
        channels: 2
      })

      payload = collect_sink_payload(pipeline)
      assert byte_size(payload) > 0

      left_channel = payload |> PCM.decode_stereo() |> Enum.map(&elem(&1, 0))
      target_mag = goertzel_magnitude(left_channel, 1000.0, @sample_rate)
      off_target_mag = goertzel_magnitude(left_channel, 6000.0, @sample_rate)

      assert target_mag > off_target_mag * 5,
             "expected strong energy at 1000Hz (#{target_mag}) relative to 6000Hz (#{off_target_mag})"

      Testing.Pipeline.terminate(pipeline)
    end
  end

  describe "AACEncoder" do
    test "encodes PCM into ADTS AAC bytes that ffmpeg itself can decode back to the right tone" do
      freq = 800.0

      # ffmpeg's AAC encoder+muxer over a pipe has an inherent ~1.5-2s
      # startup priming latency before its first output packet (see the
      # element's moduledoc) — use a clip comfortably longer than that so
      # this test exercises real steady-state output, not the priming
      # window.
      pcm =
        for i <- 0..round(3.0 * @sample_rate - 1) do
          s = 0.4 * :math.sin(2 * :math.pi() * freq * i / @sample_rate)
          {s, s}
        end
        |> PCM.encode_stereo()

      spec =
        child(:source, %Testing.Source{
          output: [%Membrane.Buffer{payload: pcm}],
          stream_format: %RawAudio{sample_format: :s16le, sample_rate: @sample_rate, channels: 2}
        })
        |> child(:encoder, AACEncoder)
        |> child(:sink, Testing.Sink)

      pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

      assert_sink_stream_format(pipeline, :sink, %RemoteStream{
        content_format: Membrane.AAC,
        type: :bytestream
      })

      adts_out = collect_sink_payload(pipeline)
      assert byte_size(adts_out) > 0

      # Round-trip the encoder's actual output through ffmpeg's own
      # decoder — independent verification that these bytes are valid,
      # standards-conformant ADTS AAC, not just "some bytes we produced".
      in_path =
        Path.join(
          System.tmp_dir!(),
          "agora-aac-encoder-out-#{System.unique_integer([:positive])}.adts"
        )

      out_path = String.replace(in_path, ".adts", ".pcm")
      File.write!(in_path, adts_out)

      {_out, 0} =
        System.cmd("ffmpeg", [
          "-hide_banner",
          "-loglevel",
          "error",
          "-f",
          "aac",
          "-i",
          in_path,
          "-f",
          "s16le",
          "-ar",
          "#{@sample_rate}",
          "-ac",
          "2",
          "-y",
          out_path
        ])

      decoded_left = out_path |> File.read!() |> PCM.decode_stereo() |> Enum.map(&elem(&1, 0))
      File.rm!(in_path)
      File.rm!(out_path)

      target_mag = goertzel_magnitude(decoded_left, freq, @sample_rate)
      off_target_mag = goertzel_magnitude(decoded_left, 5000.0, @sample_rate)

      assert target_mag > off_target_mag * 5,
             "expected strong energy at #{freq}Hz (#{target_mag}) relative to 5000Hz (#{off_target_mag})"

      Testing.Pipeline.terminate(pipeline)
    end
  end

  describe "full decode -> effects -> encode round trip" do
    test "a tone survives decode -> effects (bypass) -> encode with its frequency intact" do
      freq = 1200.0
      # Needs to clear the encoder's ~1.5-2s priming latency (see
      # AACEncoder's moduledoc) with room to spare for real output.
      adts = synth_adts!(freq, 3.5)
      chunks = chunk_binary(adts, 4096)

      bypass_params =
        Params.default()
        |> Map.update!(:noise_gate, &Map.put(&1, :enabled, false))
        |> Map.update!(:eq, fn eq ->
          Map.new(eq, fn {band, p} -> {band, Map.put(p, :enabled, false)} end)
        end)
        |> Map.update!(:compressor, &Map.put(&1, :enabled, false))
        |> Map.update!(:reverb, &Map.put(&1, :enabled, false))
        |> Map.update!(:limiter, &Map.put(&1, :enabled, false))

      spec =
        child(:source, %Testing.Source{
          output: Enum.map(chunks, &%Membrane.Buffer{payload: &1}),
          stream_format: %AAC{sample_rate: @sample_rate, channels: 2, encapsulation: :ADTS}
        })
        |> child(:decoder, AACDecoder)
        |> child(:effects, %EffectsFilter{initial_params: bypass_params})
        |> child(:encoder, AACEncoder)
        |> child(:reparser, %AAC.Parser{out_encapsulation: :ADTS})
        |> child(:sink, Testing.Sink)

      pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

      # Chains decode -> effects -> AACEncoder, so the first stream_format
      # notification out of :sink inherits AACEncoder's own ~1.5-2s ffmpeg
      # startup priming latency (see its moduledoc) on top of decode/effects
      # time — comfortably past assert_sink_stream_format/4's 2000ms
      # default, which made this specific (chained) test flaky where the
      # standalone AACEncoder test above, with the same default, wasn't.
      assert_sink_stream_format(pipeline, :sink, %AAC{encapsulation: :ADTS}, 10_000)

      adts_out = collect_sink_payload(pipeline)
      assert byte_size(adts_out) > 0

      in_path =
        Path.join(System.tmp_dir!(), "agora-roundtrip-#{System.unique_integer([:positive])}.adts")

      out_path = String.replace(in_path, ".adts", ".pcm")
      File.write!(in_path, adts_out)

      {_out, 0} =
        System.cmd("ffmpeg", [
          "-hide_banner",
          "-loglevel",
          "error",
          "-f",
          "aac",
          "-i",
          in_path,
          "-f",
          "s16le",
          "-ar",
          "#{@sample_rate}",
          "-ac",
          "2",
          "-y",
          out_path
        ])

      decoded_left = out_path |> File.read!() |> PCM.decode_stereo() |> Enum.map(&elem(&1, 0))
      File.rm!(in_path)
      File.rm!(out_path)

      target_mag = goertzel_magnitude(decoded_left, freq, @sample_rate)
      off_target_mag = goertzel_magnitude(decoded_left, 4000.0, @sample_rate)

      assert target_mag > off_target_mag * 5,
             "expected the #{freq}Hz tone to survive the full round trip intact"

      Testing.Pipeline.terminate(pipeline)
    end
  end

  # ffmpeg's stdout arrives across multiple async {:data, ...} port
  # messages, each forwarded downstream as its own buffer — so unlike a
  # single assert_sink_buffer/4 call, collect every buffer the sink
  # receives until its :input pad reaches end_of_stream. This matches
  # exactly how Membrane.Testing.Pipeline forwards Testing.Sink's own
  # notify_parent calls (see Membrane.Testing.Sink.handle_buffer/4 and
  # .handle_end_of_stream/3): {Membrane.Testing.Pipeline, pipeline,
  # {:handle_child_notification, {payload, :sink}}}.
  defp collect_sink_payload(pipeline, acc \\ []) do
    receive do
      {Testing.Pipeline, ^pipeline, {:handle_child_notification, {{:buffer, buffer}, :sink}}} ->
        collect_sink_payload(pipeline, [buffer.payload | acc])

      {Testing.Pipeline, ^pipeline,
       {:handle_child_notification, {{:end_of_stream, :input}, :sink}}} ->
        acc |> Enum.reverse() |> IO.iodata_to_binary()
    after
      # Generous: covers AACEncoder's ~3s end-of-stream flush grace
      # period (see its moduledoc) plus real ffmpeg processing time.
      10_000 -> flunk("timed out waiting for :sink to reach end_of_stream")
    end
  end
end
