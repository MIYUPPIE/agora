defmodule Agora.Workers.ArchiveGathering do
  @moduledoc """
  When a Gathering ends, its full segment set already exists on disk —
  archiving it is just one FFmpeg stream-copy concat away. This turns
  that into a downloadable, feed-visible replay Post on the
  broadcaster's own profile, and — while the same temp clip is still on
  disk, before `Media.build_clip/4`'s temp dir gets cleaned up — runs
  the accurate, non-real-time transcription pass over the *entire*
  Gathering with `Agora.Media.Audio.WhisperCli`, replacing whatever
  provisional `:live` captions `Agora.Media.Audio.Transcriber` produced
  during the broadcast with one polished `:final` transcript (see
  `Agora.Transcripts.replace_final!/2`).

  Deliberately one job, not two: transcription reuses the exact clip
  this job already built for the replay archive rather than having a
  separate job re-run `Media.build_clip/4`'s ffmpeg concat a second
  time. A transcription failure (whisper.cpp not installed, a bad audio
  file) is logged and swallowed rather than failing the whole job —
  the replay Post publishing is the part listeners actually notice;
  losing the accurate transcript still leaves the live captions in
  place as a fallback rather than nothing at all.
  """

  use Oban.Worker, queue: :media, max_attempts: 3

  require Logger
  alias Agora.{Gatherings, Media, Posts, Transcripts}
  alias Agora.Media.Audio.WhisperCli
  alias Agora.Media.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"gathering_id" => gathering_id}}) do
    gathering = Gatherings.get!(gathering_id)
    to_seq = Media.current_sequence(gathering_id)

    case Media.build_clip(gathering_id, 0, to_seq) do
      {:ok, path, byte_size} ->
        try do
          transcribe_final(gathering, path)
          upload_and_publish(gathering, path, byte_size)
        after
          File.rm_rf(Path.dirname(path))
        end

      {:error, :no_segments} ->
        Logger.info("Gathering #{gathering_id} ended with no segments — nothing to archive")
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to build archive clip for gathering #{gathering_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp transcribe_final(gathering, path) do
    case WhisperCli.transcribe_file(path) do
      {:ok, []} ->
        :ok

      {:ok, segments} ->
        Transcripts.replace_final!(gathering.id, segments)
        Transcripts.notify_ready(gathering.user_id, gathering.id)

      {:error, :unavailable} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Final transcription failed for gathering #{gathering.id}: #{inspect(reason)} " <>
            "— keeping whatever live captions it already has, if any"
        )
    end
  end

  defp upload_and_publish(gathering, path, byte_size) do
    key = "gatherings/#{gathering.id}/replay.m4a"

    with {:ok, url} <- Storage.put(path, key, "audio/mp4"),
         duration_ms = Media.ffprobe_duration_ms(path) || 0,
         {:ok, _post} <-
           Posts.create_audio_post(
             gathering.user_id,
             %{"title" => gathering.title, "duration_ms" => duration_ms},
             %{url: url, byte_size: byte_size}
           ) do
      :ok
    end
  end
end
