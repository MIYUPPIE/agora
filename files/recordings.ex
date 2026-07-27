defmodule Agora.Recordings do
  @moduledoc """
  Listener-side recording of a live Gathering.

  The trick: "recording" stores no audio. It stores two integers.

    Record pressed  -> start_seq = current head segment
    Stop pressed    -> end_seq   = current head segment, enqueue ClipBuilder

  The ClipBuilder job then concatenates the already-existing HLS segments
  (stream copy, no re-encode) into a downloadable file. A thousand
  listeners recording simultaneously costs the server nothing until they
  each stop — and each stop is one cheap FFmpeg concat.
  """

  import Ecto.Query
  alias Agora.Repo
  alias Agora.Recordings.Recording
  alias Agora.Media

  def start_recording(user_id, gathering_id) do
    %Recording{}
    |> Recording.changeset(%{
      user_id: user_id,
      gathering_id: gathering_id,
      start_seq: Media.current_sequence(gathering_id),
      status: :recording
    })
    |> Repo.insert()
  end

  @doc "Record-from-the-beginning: same thing with start_seq = 0."
  def record_from_start(user_id, gathering_id) do
    %Recording{}
    |> Recording.changeset(%{
      user_id: user_id,
      gathering_id: gathering_id,
      start_seq: 0,
      status: :recording
    })
    |> Repo.insert()
  end

  def stop_recording(%Recording{status: :recording} = recording) do
    recording
    |> Recording.changeset(%{
      end_seq: Media.current_sequence(recording.gathering_id),
      status: :processing
    })
    |> Repo.update()
    |> case do
      {:ok, recording} ->
        {:ok, _job} =
          %{recording_id: recording.id}
          |> Agora.Workers.ClipBuilder.new()
          |> Oban.insert()

        {:ok, recording}

      error ->
        error
    end
  end

  def get!(id), do: Repo.get!(Recording, id)

  def active_for(user_id, gathering_id) do
    Recording
    |> where(user_id: ^user_id, gathering_id: ^gathering_id, status: :recording)
    |> Repo.one()
  end
end

defmodule Agora.Recordings.Recording do
  use Ecto.Schema
  import Ecto.Changeset

  schema "recordings" do
    belongs_to :user, Agora.Accounts.User
    belongs_to :gathering, Agora.Gatherings.Gathering

    field :start_seq, :integer
    field :end_seq, :integer
    field :status, Ecto.Enum, values: [:recording, :processing, :ready, :failed]
    field :download_url, :string
    field :byte_size, :integer

    timestamps()
  end

  def changeset(recording, attrs) do
    recording
    |> cast(attrs, [:user_id, :gathering_id, :start_seq, :end_seq, :status, :download_url, :byte_size])
    |> validate_required([:user_id, :gathering_id, :start_seq, :status])
  end
end

defmodule Agora.Media.GatheringSegment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "gathering_segments" do
    belongs_to :gathering, Agora.Gatherings.Gathering
    field :sequence, :integer
    field :filename, :string
    field :byte_size, :integer
    field :duration_ms, :integer
    timestamps(updated_at: false)
  end

  def changeset(segment, attrs) do
    segment
    |> cast(attrs, [:gathering_id, :sequence, :filename, :byte_size, :duration_ms])
    |> validate_required([:gathering_id, :sequence, :filename])
    |> unique_constraint([:gathering_id, :sequence])
  end
end
