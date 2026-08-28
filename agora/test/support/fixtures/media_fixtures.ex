defmodule Agora.MediaFixtures do
  @moduledoc """
  Generates real fMP4 HLS fragments via ffmpeg (an init header + N
  one-second segments) and inserts matching gathering_segments rows —
  the same shape Membrane's SinkBin/SegmentStorage produce in
  production, without needing a real RTMP stream in the test suite.
  """

  alias Agora.Media

  def write_synthetic_segments!(gathering_id, duration_seconds: seconds) do
    dir = Media.segment_dir(gathering_id)
    File.mkdir_p!(dir)

    {_out, 0} =
      System.cmd(
        "ffmpeg",
        ~w(-f lavfi -i) ++
          ["sine=frequency=440:duration=#{seconds}"] ++
          ~w(-c:a aac -b:a 64k -f hls -hls_time 1 -hls_segment_type fmp4
             -hls_fmp4_init_filename muxed_header_test.mp4
             -hls_flags independent_segments
             -hls_segment_filename) ++
          [Path.join(dir, "seg_%d.m4s"), Path.join(dir, "out.m3u8")],
        stderr_to_stdout: true
      )

    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".m4s"))
    |> Enum.sort()
    |> Enum.with_index()
    |> Enum.each(fn {filename, seq} ->
      Media.insert_segment!(%{gathering_id: gathering_id, sequence: seq, filename: filename})
    end)
  end

  @doc """
  Synthesizes real, whisper-transcribable speech via ffmpeg's built-in
  `flite` TTS source filter (confirmed hands-on: `libflite` is already
  compiled into this host's ffmpeg, and a real whisper.cpp model
  transcribes its output correctly) — raw s16le stereo PCM at the
  Gathering pipeline's native 48kHz, ready to feed straight into
  `Agora.Media.Audio.UtteranceBuffer`/`Transcriber` or wrap with
  `Agora.Media.Audio.Wav.encode/3`. Deterministic and dependency-free
  (no committed audio fixture, no network) — the whole point of using
  it instead of a vendored sample file.
  """
  def synth_speech_pcm!(text, opts \\ []) do
    sample_rate = Keyword.get(opts, :sample_rate, 48_000)
    channels = Keyword.get(opts, :channels, 2)
    voice = Keyword.get(opts, :voice, "slt")

    {pcm, 0} =
      System.cmd(
        "ffmpeg",
        ~w(-hide_banner -loglevel error -f lavfi -i) ++
          ["flite=text='#{escape(text)}':voice=#{voice}"] ++
          ~w(-f s16le -ar #{sample_rate} -ac #{channels} pipe:1),
        []
      )

    pcm
  end

  defp escape(text), do: String.replace(text, "'", "")
end
