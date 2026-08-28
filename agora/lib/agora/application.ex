defmodule Agora.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if Application.get_env(:agora, :dev_routes) do
      # The LAN dev setup intentionally runs plain HTTP on :4000 alongside
      # HTTPS on :4001 (see config/dev.exs). A phone's HTTPS-first connection
      # heuristic routinely probes :4000 before falling back, which Bandit
      # logs as "Connection that looks like TLS received on a clear channel"
      # — non-actionable noise, so drop it below :error.
      Logger.put_module_level(Bandit.InitialHandler, :error)
    end

    if media_root = Application.get_env(:agora, :media_root) do
      File.mkdir_p!(media_root)
    end

    children =
      [
        AgoraWeb.Telemetry,
        Agora.Repo,
        {DNSCluster, query: Application.get_env(:agora, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Agora.PubSub},
        AgoraWeb.Presence,
        {Oban, Application.fetch_env!(:agora, Oban)},
        Agora.Media.GatheringRegistry,
        Agora.Media.GatheringSupervisor,
        # Runs the Task.Supervisor.start_child call in
        # Agora.Media.Audio.Transcriber — off the Membrane pipeline
        # process, so a slow/failed whisper-server request never stalls
        # live audio.
        {Task.Supervisor, name: Agora.TaskSupervisor}
      ] ++
        rtmp_server_child() ++
        whisper_server_child() ++
        [
          # Start to serve requests, typically the last entry
          AgoraWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Agora.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tests don't need a real TCP listener on :1935, and starting one would
  # collide with a `mix phx.server` already running in dev on the same port.
  defp rtmp_server_child do
    if Application.get_env(:agora, :start_rtmp_server, true) do
      [
        {Membrane.RTMPServer,
         port: Application.get_env(:agora, :rtmp_port, 1935),
         handle_new_client: &Agora.Media.RTMPEndpoint.handle_new_client/3}
      ]
    else
      []
    end
  end

  # Tests start/stop their own throwaway whisper-server instances instead
  # (see config/test.exs) so they don't race a shared one across the
  # suite, and so a machine without scripts/setup_whisper.sh having been
  # run yet doesn't fail to boot the app at all — see
  # Agora.Media.Audio.WhisperServer's moduledoc for the full
  # self-disabling story.
  defp whisper_server_child do
    if Application.get_env(:agora, :start_whisper_server, true) do
      [Agora.Media.Audio.WhisperServer]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AgoraWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
