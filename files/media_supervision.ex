defmodule Agora.Media do
  @moduledoc "Helpers shared by the media layer."

  import Ecto.Query
  alias Agora.Repo
  alias Agora.Media.GatheringSegment

  def segment_dir(gathering_id),
    do: Path.join([Application.fetch_env!(:agora, :media_root), "gatherings", to_string(gathering_id)])

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
end

defmodule Agora.Media.GatheringRegistry do
  @moduledoc "Registry mapping gathering_id -> pipeline pid."
  def child_spec(_), do: Registry.child_spec(keys: :unique, name: __MODULE__)
end

defmodule Agora.Media.GatheringSupervisor do
  @moduledoc "DynamicSupervisor owning one GatheringPipeline per live stream."
  use DynamicSupervisor

  def start_link(init_arg),
    do: DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)

  @impl true
  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_gathering(gathering_id, client_ref) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Agora.Media.GatheringPipeline, gathering_id: gathering_id, client_ref: client_ref}
    )
  end
end

defmodule Agora.Media.RTMPEndpoint do
  @moduledoc """
  RTMP ingest endpoint.

  Broadcasters stream to:  rtmp://ingest.agora.example/live/<stream_key>

  The stream key is a per-Gathering secret generated when the user taps
  "Start Gathering" in the app. We validate it here and only then spin up
  a pipeline — unknown keys are dropped before they cost us anything.

  Add to your application children:

      {Membrane.RTMPServer,
       port: 1935,
       handle_new_client: &Agora.Media.RTMPEndpoint.handle_new_client/3}
  """

  require Logger

  def handle_new_client(client_ref, _app, stream_key) do
    case Agora.Gatherings.get_by_stream_key(stream_key) do
      %{id: gathering_id, status: status} when status in [:scheduled, :live] ->
        {:ok, _pid} = Agora.Media.GatheringSupervisor.start_gathering(gathering_id, client_ref)
        Logger.info("Gathering #{gathering_id} ingest connected")
        # Tell the RTMP server which message handler owns this client.
        {Membrane.RTMP.Source.ClientHandlerImpl, client_ref}

      _ ->
        Logger.warning("Rejected RTMP connect with bad stream key")
        :reject
    end
  end
end
