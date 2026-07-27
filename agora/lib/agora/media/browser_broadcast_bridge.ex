defmodule Agora.Media.BrowserBroadcastBridge do
  @moduledoc """
  Lets a broadcaster go live straight from their phone/laptop browser,
  with no OBS or external encoder required.

  The browser captures mic audio with MediaRecorder (webm/opus) and
  streams chunks over `AgoraWeb.BroadcastChannel`. This GenServer pipes
  those chunks into an ffmpeg process's stdin, which re-encodes them to
  AAC and pushes RTMP at `Agora.Gatherings.local_ingest_url/1` — i.e.
  loopback into the exact same `Membrane.RTMPServer` port that a real
  OBS connection would use.

  This is the whole point of the design: from `Agora.Media.RTMPEndpoint`
  and `Agora.Media.GatheringPipeline` down, an ffmpeg-bridged browser
  broadcast is indistinguishable from OBS. Zero changes needed to the
  pipeline, the RTMP validation, or the segment storage — all of that
  was already built and tested in Phase 4/5 against exactly this kind of
  RTMP client.

  One instance per active browser broadcast, started (and linked) by
  `AgoraWeb.BroadcastChannel.join/3` for the lifetime of that channel.
  """

  use GenServer
  require Logger

  alias Agora.Gatherings

  @doc """
  `channel_pid` receives `{:ffmpeg_exited, status}` if ffmpeg exits
  unexpectedly (status != 0) so the channel can tell the browser instead
  of silently going dark.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def push_chunk(pid, data) when is_binary(data), do: GenServer.cast(pid, {:chunk, data})

  def stop(pid), do: GenServer.stop(pid, :normal, 5_000)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    gathering = Keyword.fetch!(opts, :gathering)
    channel_pid = Keyword.fetch!(opts, :channel_pid)

    executable =
      Application.get_env(:agora, :browser_broadcast_ffmpeg, "ffmpeg") |> System.find_executable()

    unless executable do
      raise "ffmpeg executable not found on PATH"
    end

    rtmp_url = Gatherings.local_ingest_url(gathering)

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        args: ffmpeg_args(rtmp_url)
      ])

    Logger.info("browser broadcast bridge started for gathering #{gathering.id}")

    {:ok, %{port: port, channel_pid: channel_pid, gathering_id: gathering.id}}
  end

  defp ffmpeg_args(rtmp_url) do
    case Application.get_env(:agora, :browser_broadcast_ffmpeg_args) do
      fun when is_function(fun, 1) -> fun.(rtmp_url)
      nil -> default_ffmpeg_args(rtmp_url)
    end
  end

  defp default_ffmpeg_args(rtmp_url) do
    ~w(-loglevel error -nostats
       -f webm -i pipe:0
       -c:a aac -b:a 64k -ar 48000
       -f flv) ++ [rtmp_url]
  end

  @impl true
  def handle_cast({:chunk, data}, %{port: port} = state) do
    # The browser keeps recording (and pushing chunks) even for a moment
    # after we've asked it to stop, and the port may already be gone by
    # then — drop those stragglers instead of crashing on a closed port.
    if Port.info(port), do: Port.command(port, data)
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, _}}, %{port: port} = state) do
    # ffmpeg with -loglevel error -nostats should be silent on stdout;
    # anything that does arrive here is harmless and ignored.
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, 0}}, %{port: port} = state) do
    Logger.info("browser broadcast bridge for gathering #{state.gathering_id} ended cleanly")
    {:stop, :normal, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning(
      "browser broadcast bridge for gathering #{state.gathering_id} ffmpeg exited #{status}"
    )

    send(state.channel_pid, {:ffmpeg_exited, status})
    {:stop, :normal, state}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{port: port}) do
    if Port.info(port), do: Port.close(port)
    :ok
  end
end
