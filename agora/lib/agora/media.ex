defmodule Agora.Media do
  @moduledoc """
  Helpers shared by the live media layer: where a Gathering's HLS
  segments live on disk, and the DB rows that track them.

  This is the hinge of the record-and-download feature (Phase 5): a
  listener's "Record" press just snapshots `current_sequence/1` — no
  media work happens until they press Stop.
  """

  import Ecto.Query
  alias Agora.Repo
  alias Agora.Media.GatheringSegment

  def segment_dir(gathering_id),
    do:
      Path.join([
        Application.fetch_env!(:agora, :media_root),
        "gatherings",
        to_string(gathering_id)
      ])

  def insert_segment!(attrs) do
    %GatheringSegment{}
    |> GatheringSegment.changeset(attrs)
    |> Repo.insert!()
  end

  @doc "Head sequence number for a live gathering (what 'now' means)."
  def current_sequence(gathering_id) do
    GatheringSegment
    |> where(gathering_id: ^gathering_id)
    |> select([s], max(s.sequence))
    |> Repo.one() || 0
  end

  def segments_in_range(gathering_id, from_seq, to_seq) do
    GatheringSegment
    |> where(gathering_id: ^gathering_id)
    |> where([s], s.sequence >= ^from_seq and s.sequence <= ^to_seq)
    |> order_by(asc: :sequence)
    |> Repo.all()
  end

  @doc """
  Concatenates a Gathering's already-existing HLS segments (start_seq to
  end_seq inclusive) into a single downloadable audio file. Shared by
  the ClipBuilder (Phase 5, listener recordings) and ArchiveGathering
  (Phase 4, full-gathering replay) workers.

  Two steps, both discovered by testing against real ffmpeg-generated
  fMP4 fragments rather than trusted on faith:

    1. fMP4/CMAF fragments (what `SinkBin` writes) concatenate as **raw
       bytes** — `init_header ++ frag1 ++ frag2 ++ ...` is itself a
       valid fragmented MP4 file. This is *not* the same as FFmpeg's
       `-f concat` demuxer: that demuxer tries to open each listed file
       as its own standalone container, and a bare `.m4s` fragment
       (moof+mdat, no ftyp/moov of its own) fails to demux on its own —
       `-f concat` produced an empty, unplayable output; binary
       concatenation produced a correct file.

    2. That raw-concatenated file must then be **remuxed with
       `-avoid_negative_ts make_zero`**, even when just stream-copying
       to m4a with no re-encode. fMP4 fragments carry decode timestamps
       *absolute to the original stream*, not relative to where the
       clip starts — a recording of segments 20-22 (say) carries the
       stream's original ~80s timestamp on its first frame. Skip this
       step and the file plays its ~4s of real audio correctly, but any
       player that reads container-level duration/seek metadata without
       fully decoding (which is most of them) shows a nonsensical ~84s
       duration with a seek bar that's silent for all but the last few
       seconds. Only full-gathering replays (always starting at
       segment 0) would happen to look right without this; any
       listener recording that doesn't start from the beginning would
       not.

  Returns `{:ok, path, byte_size}` for a file under a *caller-owned* tmp
  directory — remove `Path.dirname(path)` once you're done with it.
  """
  def build_clip(gathering_id, from_seq, to_seq, format \\ "m4a") do
    case segments_in_range(gathering_id, from_seq, to_seq) do
      [] ->
        {:error, :no_segments}

      segments ->
        dir = segment_dir(gathering_id)
        tmp = Path.join(System.tmp_dir!(), "agora_clip_#{System.unique_integer([:positive])}")
        File.mkdir_p!(tmp)

        init = Path.join(dir, init_header_name(dir))
        concatenated = Path.join(tmp, "concatenated.mp4")

        File.open!(concatenated, [:write], fn out_file ->
          for path <- [init | Enum.map(segments, &Path.join(dir, &1.filename))] do
            IO.binwrite(out_file, File.read!(path))
          end
        end)

        out_path = Path.join(tmp, "clip.#{format}")
        codec_args = if format == "mp3", do: ~w(-c:a libmp3lame -b:a 128k), else: ~w(-c copy)

        args =
          ["-y", "-i", concatenated] ++
            codec_args ++ ["-avoid_negative_ts", "make_zero", "-vn", out_path]

        case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
          {_out, 0} -> {:ok, out_path, File.stat!(out_path).size}
          {out, code} -> {:error, {:ffmpeg_failed, code, out}}
        end
    end
  end

  defp init_header_name(dir) do
    # SinkBin writes one init header per track, e.g. "muxed_header_..._part0.mp4"
    dir
    |> File.ls!()
    |> Enum.find(&String.contains?(&1, "header"))
  end

  @doc "Exact duration of a media file in milliseconds, via ffprobe."
  def ffprobe_duration_ms(path) do
    args = ~w(-v quiet -show_entries format=duration -of csv=p=0) ++ [path]

    case System.cmd("ffprobe", args) do
      {out, 0} ->
        case Float.parse(String.trim(out)) do
          {seconds, _} -> round(seconds * 1000)
          :error -> nil
        end

      _ ->
        nil
    end
  end
end
