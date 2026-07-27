defmodule Agora.Media.SegmentStorage do
  @moduledoc """
  Custom storage backend for Membrane's HLS sink.

  This is the hinge of the whole record-and-download feature. Every time
  the packager emits a file we:

    1. write it to disk (nginx/Phoenix serves it, CDN caches it),
    2. if it's a media segment, insert a `gathering_segments` row with a
       monotonically increasing sequence number,
    3. broadcast the new head sequence on PubSub.

  A listener pressing "Record" just snapshots the current head sequence.
  No per-listener media work happens during the stream at all.
  """

  @behaviour Membrane.HTTPAdaptiveStream.Storage

  @enforce_keys [:gathering_id, :directory]
  defstruct @enforce_keys ++ [seq: 0]

  alias Agora.Media

  @impl true
  def init(%__MODULE__{} = config), do: config

  @impl true
  def store(_parent_id, name, contents, _metadata, %{mode: :binary, type: :segment}, state) do
    path = Path.join(state.directory, name)

    with :ok <- File.write(path, contents) do
      seq = state.seq

      # Persist segment metadata. Duration is fixed by the pipeline's
      # segment_duration; storing it per-row keeps the clip math honest
      # if you ever change it.
      Media.insert_segment!(%{
        gathering_id: state.gathering_id,
        sequence: seq,
        filename: name,
        byte_size: byte_size(contents),
        duration_ms: 4_000
      })

      Phoenix.PubSub.broadcast(
        Agora.PubSub,
        "gathering:#{state.gathering_id}:segments",
        {:segment, seq}
      )

      {:ok, %{state | seq: seq + 1}}
    end
  end

  # Init headers (fMP4) and any other binary files: just write them.
  def store(_parent_id, name, contents, _metadata, %{mode: :binary}, state) do
    with :ok <- File.write(Path.join(state.directory, name), contents), do: {:ok, state}
  end

  # Manifests (.m3u8) are text-mode and rewritten constantly.
  def store(_parent_id, name, contents, _metadata, %{mode: :text}, state) do
    with :ok <- File.write(Path.join(state.directory, name), contents), do: {:ok, state}
  end

  @impl true
  def remove(_parent_id, name, _ctx, state) do
    # With target_window_duration: :infinity this rarely fires, but honor it.
    File.rm(Path.join(state.directory, name))
    {:ok, state}
  end
end
