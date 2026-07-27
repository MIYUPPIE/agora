defmodule Agora.Gatherings do
  @moduledoc """
  Live Gatherings: the audio broadcast lifecycle (scheduled -> live ->
  ended). The media pipeline itself lives in `Agora.Media.*` — this
  context only owns the row: who's broadcasting, under what stream key,
  and what state they're in.
  """

  import Ecto.Query

  alias Agora.Gatherings.Gathering
  alias Agora.Repo

  def get!(id), do: Repo.get!(Gathering, id) |> Repo.preload(user: :profile)

  def get_by_stream_key(stream_key), do: Repo.get_by(Gathering, stream_key: stream_key)

  @doc "Creates a scheduled Gathering with a fresh, unguessable stream key."
  def create_gathering(user_id, attrs) do
    %Gathering{}
    |> Gathering.changeset(
      Map.merge(attrs, %{"user_id" => user_id, "stream_key" => generate_stream_key()})
    )
    |> Repo.insert()
  end

  defp generate_stream_key, do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)

  @doc "Flips a Gathering live. Called by GatheringPipeline when the encoder connects."
  def mark_live!(gathering_id) do
    now = DateTime.utc_now(:second)

    {1, _} =
      Gathering
      |> where(id: ^gathering_id)
      |> Repo.update_all(set: [status: :live, started_at: now])

    :ok
  end

  @doc "Flips a Gathering ended. Called when the broadcaster's encoder disconnects."
  def mark_ended!(gathering_id) do
    now = DateTime.utc_now(:second)

    {1, _} =
      Gathering
      |> where(id: ^gathering_id)
      |> Repo.update_all(set: [status: :ended, ended_at: now])

    :ok
  end

  @doc "The RTMP ingest URL a broadcaster points OBS/their encoder at."
  def ingest_url(%Gathering{stream_key: stream_key}) do
    host = Application.get_env(:agora, :rtmp_host, "localhost")
    "rtmp://#{host}:#{rtmp_port()}/live/#{stream_key}"
  end

  @doc """
  The RTMP URL used by `Agora.Media.BrowserBroadcastBridge`'s ffmpeg
  process — always 127.0.0.1, never the public host, because that
  process runs on the same box as `Membrane.RTMPServer` and reaches it
  over loopback rather than the public network.
  """
  def local_ingest_url(%Gathering{stream_key: stream_key}) do
    "rtmp://127.0.0.1:#{rtmp_port()}/live/#{stream_key}"
  end

  defp rtmp_port, do: Application.get_env(:agora, :rtmp_port, 1935)

  @doc "The HLS manifest URL a listener's <audio> hook loads."
  def manifest_url(%Gathering{id: id}), do: "/media/gatherings/#{id}/index.m3u8"

  @doc "Gatherings currently live, newest-started first — for a 'Join a Gathering' browse view."
  def list_live do
    Gathering
    |> where(status: :live)
    |> order_by(desc: :started_at)
    |> preload(user: :profile)
    |> Repo.all()
  end

  def count_for_user(user_id) do
    Gathering |> where(user_id: ^user_id) |> Repo.aggregate(:count)
  end
end
