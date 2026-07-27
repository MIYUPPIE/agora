defmodule Agora.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
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
        Agora.Media.GatheringSupervisor
      ] ++
        rtmp_server_child() ++
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

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AgoraWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
