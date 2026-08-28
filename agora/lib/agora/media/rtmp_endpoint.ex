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

            reject_connection()
        end

      _ ->
        Logger.warning("Rejected RTMP connect with bad stream key")
        reject_connection()
    end
  end

  # membrane_rtmp_plugin 0.29.5's `client_behaviour_spec` has no "reject"
  # case: whatever handle_new_client/3 returns is treated as a handler
  # module (or `{module, opts}`) and gets `handler_module.handle_init/1`
  # called on it unconditionally (client_handler.ex:198). Returning a bare
  # `:reject` atom used to satisfy that contract for the wrong reason —
  # `:reject` looks like a sentinel but is just an atom, so Elixir tried to
  # call `:reject.handle_init/1` and crashed the connection's GenServer
  # with an UndefinedFunctionError on every single bad stream key.
  #
  # handle_new_client/3 always runs synchronously inside that connection's
  # own `Membrane.RTMPServer.ClientHandler` GenServer (it's invoked
  # straight from that process's own handle_data/2), so exiting *this*
  # process here drops only this one client. The reason must be `:normal`:
  # `GenServer.start_link/3` links each ClientHandler to
  # `Membrane.RTMPServer.Listener`'s accept-loop Task, and any other exit
  # reason — `:shutdown` included — propagates through that link and takes
  # the whole accept loop (every other broadcaster's connection) down with
  # it. `:normal` is also the one reason that closes the client's TCP
  # socket without logging a crash report. Confirmed against a live
  # gen_tcp socket and a linked parent process before relying on it here.
  @spec reject_connection() :: no_return()
  defp reject_connection, do: exit(:normal)
end
