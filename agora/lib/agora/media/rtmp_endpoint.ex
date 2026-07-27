defmodule Agora.Media.RTMPEndpoint do
  @moduledoc """
  RTMP ingest endpoint.

  Broadcasters stream to:  rtmp://ingest.agora.example/live/<stream_key>

  The stream key is a per-Gathering secret generated when the user taps
  "Start Gathering" in the app. We validate it here and only then spin up
  a pipeline — unknown keys are dropped before they cost us anything.
  """

  require Logger

  def handle_new_client(client_ref, _app, stream_key) do
    case Agora.Gatherings.get_by_stream_key(stream_key) do
      %{id: gathering_id, status: status} when status in [:scheduled, :live] ->
        case Agora.Media.GatheringSupervisor.start_gathering(gathering_id, client_ref) do
          # Membrane.Pipeline.start_link/3 returns {:ok, supervisor_pid, pipeline_pid} —
          # DynamicSupervisor.start_child/2 passes that 3-tuple straight through, so
          # match both shapes rather than assume the plain {:ok, pid} of an OTP GenServer.
          {:ok, _pid} ->
            Logger.info("Gathering #{gathering_id} ingest connected")
            {Membrane.RTMP.Source.ClientHandlerImpl, client_ref}

          {:ok, _pid, _info} ->
            Logger.info("Gathering #{gathering_id} ingest connected")
            {Membrane.RTMP.Source.ClientHandlerImpl, client_ref}

          {:error, reason} ->
            Logger.error(
              "Failed to start pipeline for gathering #{gathering_id}: #{inspect(reason)}"
            )

            :reject
        end

      _ ->
        Logger.warning("Rejected RTMP connect with bad stream key")
        :reject
    end
  end
end
