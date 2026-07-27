defmodule Agora.Workers.ClipBuilder do
  @moduledoc """
  Turns a listener's Recording (start_seq..end_seq) into a downloadable
  .m4a and pushes the link back to their LiveView over PubSub.
  """

  use Oban.Worker, queue: :media, max_attempts: 3

  require Logger
  alias Agora.{Media, Recordings}
  alias Agora.Media.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"recording_id" => recording_id} = args}) do
    recording = Recordings.get!(recording_id)
    format = Map.get(args, "format", "m4a")

    case Media.build_clip(recording.gathering_id, recording.start_seq, recording.end_seq, format) do
      {:ok, path, byte_size} ->
        try do
          upload(recording, path, byte_size, format)
        after
          File.rm_rf(Path.dirname(path))
        end

      {:error, :no_segments} ->
        fail(recording, "no segments in range")

      {:error, {:ffmpeg_failed, code, out}} ->
        Logger.error("ffmpeg failed (#{code}): #{out}")
        fail(recording, "ffmpeg exit #{code}")
    end
  end

  defp upload(recording, path, byte_size, format) do
    key = "recordings/#{recording.gathering_id}/#{recording.id}.#{format}"

    case Storage.put(path, key, content_type(format)) do
      {:ok, url} ->
        {:ok, recording} =
          recording
          |> Ecto.Changeset.change(status: :ready, download_url: url, byte_size: byte_size)
          |> Agora.Repo.update()

        Phoenix.PubSub.broadcast(
          Agora.PubSub,
          "user:#{recording.user_id}:recordings",
          {:recording_ready, recording.id, url}
        )

        :ok

      {:error, reason} ->
        fail(recording, inspect(reason))
    end
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

  defp content_type("mp3"), do: "audio/mpeg"
  defp content_type(_), do: "audio/mp4"
end
