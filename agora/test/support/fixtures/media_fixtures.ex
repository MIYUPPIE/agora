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
end
