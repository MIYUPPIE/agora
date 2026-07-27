defmodule Agora.Workers.ArchiveGathering do
  @moduledoc """
  When a Gathering ends, its full segment set already exists on disk —
  archiving it is just one FFmpeg stream-copy concat away. This turns
  that into a downloadable, feed-visible replay Post on the
  broadcaster's own profile.
  """

  use Oban.Worker, queue: :media, max_attempts: 3

  require Logger
  alias Agora.{Gatherings, Media, Posts}
  alias Agora.Media.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"gathering_id" => gathering_id}}) do
    gathering = Gatherings.get!(gathering_id)
    to_seq = Media.current_sequence(gathering_id)

    case Media.build_clip(gathering_id, 0, to_seq) do
      {:ok, path, byte_size} ->
        try do
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
