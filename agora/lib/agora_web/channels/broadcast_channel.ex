defmodule AgoraWeb.BroadcastChannel do
  @moduledoc """
  Receives a browser broadcaster's MediaRecorder audio chunks (topic
  `"broadcast:<gathering_id>"`) and hands them to
  `Agora.Media.BrowserBroadcastBridge`, which bridges them into the
  existing RTMP ingest — see that module's moduledoc for why that's the
  whole feature, with no changes to the Membrane pipeline itself.

  Join requires a `AgoraWeb.UserSocket`-verified token whose claims match
  both this exact gathering and its owner (signed by `GatheringLive.New`
  when the gathering is created — see `broadcast_token/2`).
  """

  use AgoraWeb, :channel

  alias Agora.Gatherings
  alias Agora.Media.BrowserBroadcastBridge

  @doc "Signs a token scoping browser-broadcast access to one gathering, one owner."
  def broadcast_token(gathering, user) do
    Phoenix.Token.sign(AgoraWeb.Endpoint, "browser_broadcast", %{
      gathering_id: gathering.id,
      user_id: user.id
    })
  end

  @impl true
  def join("broadcast:" <> gathering_id, _params, socket) do
    case authorize(gathering_id, socket.assigns.claims) do
      {:ok, gathering} ->
        {:ok, bridge} =
          BrowserBroadcastBridge.start_link(gathering: gathering, channel_pid: self())

        {:ok, assign(socket, :bridge, bridge)}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  defp authorize(gathering_id, claims) do
    with true <- to_string(claims.gathering_id) == gathering_id,
         gathering <- Gatherings.get!(gathering_id),
         true <- gathering.user_id == claims.user_id,
         true <- gathering.status in [:scheduled, :live] do
      {:ok, gathering}
    else
      _ -> {:error, "unauthorized"}
    end
  end

  @impl true
  def handle_in("chunk", {:binary, data}, socket) do
    BrowserBroadcastBridge.push_chunk(socket.assigns.bridge, data)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:ffmpeg_exited, status}, socket) do
    push(socket, "broadcast_error", %{status: status})
    {:stop, :normal, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if bridge = socket.assigns[:bridge], do: BrowserBroadcastBridge.stop(bridge)
    :ok
  end
end
