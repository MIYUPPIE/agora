defmodule Agora.Workers.ClipBuilder do
  @moduledoc """
  Turns a listener's Recording (start_seq..end_seq) into a downloadable
  .m4a and pushes the link back to their LiveView over PubSub.

  FFmpeg concat with `-c copy` remuxes without re-encoding, so even an
  hour-long recording builds in well under a second. We only re-encode if
  the user asked for MP3 (older phones / car stereos), which is a real
  consideration for your audience — default stays .m4a.
  """

  use Oban.Worker, queue: :media, max_attempts: 3

  require Logger
  alias Agora.{Media, Recordings}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"recording_id" => recording_id} = args}) do
    recording = Recordings.get!(recording_id)
    format = Map.get(args, "format", "m4a")

    segments =
      Media.segments_in_range(recording.gathering_id, recording.start_seq, recording.end_seq)

    if segments == [] do
      fail(recording, "no segments in range")
    else
      build_and_upload(recording, segments, format)
    end
  end

  defp build_and_upload(recording, segments, format) do
    dir = Media.segment_dir(recording.gathering_id)
    tmp = Path.join(System.tmp_dir!(), "clip_#{recording.id}")
    File.mkdir_p!(tmp)

    # 1. FFmpeg concat demuxer file list.
    #    HLS fMP4 segments need the init header first; for MPEG-TS
    #    segments plain concat works. We handle fMP4 (what SinkBin emits).
    list_path = Path.join(tmp, "list.txt")
    init = Path.join(dir, init_header_name(dir))

    entries =
      [init | Enum.map(segments, &Path.join(dir, &1.filename))]
      |> Enum.map(&"file '#{&1}'")
      |> Enum.join("\n")

    File.write!(list_path, entries)

    out_path = Path.join(tmp, "recording.#{format}")

    codec_args =
      case format do
        "mp3" -> ["-c:a", "libmp3lame", "-b:a", "128k"]
        _ -> ["-c", "copy"]
      end

    ffmpeg_args =
      ["-y", "-f", "concat", "-safe", "0", "-i", list_path] ++
        codec_args ++ ["-vn", out_path]

    case System.cmd("ffmpeg", ffmpeg_args, stderr_to_stdout: true) do
      {_out, 0} ->
        upload(recording, out_path, format)

      {out, code} ->
        Logger.error("ffmpeg failed (#{code}): #{out}")
        fail(recording, "ffmpeg exit #{code}")
    end
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "clip_#{recording.id}"))
  end

  defp upload(recording, out_path, format) do
    key = "recordings/#{recording.gathering_id}/#{recording.id}.#{format}"
    body = File.read!(out_path)

    {:ok, _} =
      ExAws.S3.put_object(bucket(), key, body,
        content_type: content_type(format),
        content_disposition: ~s(attachment; filename="agora-gathering.#{format}")
      )
      |> ExAws.request()

    url = "#{Application.fetch_env!(:agora, :cdn_base_url)}/#{key}"

    {:ok, recording} =
      recording
      |> Ecto.Changeset.change(status: :ready, download_url: url, byte_size: byte_size(body))
      |> Agora.Repo.update()

    # Wake up the listener's LiveView: their download is ready.
    Phoenix.PubSub.broadcast(
      Agora.PubSub,
      "user:#{recording.user_id}:recordings",
      {:recording_ready, recording.id, url}
    )

    :ok
  end

  defp fail(recording, reason) do
    recording
    |> Ecto.Changeset.change(status: :failed)
    |> Agora.Repo.update()

    Phoenix.PubSub.broadcast(
      Agora.PubSub,
      "user:#{recording.user_id}:recordings",
      {:recording_failed, recording.id}
    )

    {:error, reason}
  end

  defp init_header_name(dir) do
    # SinkBin writes one init header per track, e.g. "muxed_header_..._part0.mp4"
    dir
    |> File.ls!()
    |> Enum.find(&String.contains?(&1, "header"))
  end

  defp bucket, do: Application.fetch_env!(:agora, :recordings_bucket)

  defp content_type("mp3"), do: "audio/mpeg"
  defp content_type(_), do: "audio/mp4"
end
