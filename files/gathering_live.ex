defmodule AgoraWeb.GatheringLive do
  @moduledoc """
  Listener view of a live Gathering: HLS player, live listener count via
  Presence, and the Record → Stop → Download flow.

  The player itself is a tiny JS hook using hls.js — LiveView owns all
  state, the hook only attaches the manifest URL to an <audio> element.
  """

  use AgoraWeb, :live_view

  alias Agora.{Gatherings, Recordings}
  alias AgoraWeb.Presence

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    gathering = Gatherings.get!(id)
    topic = "gathering:#{gathering.id}"

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Agora.PubSub, topic)
      Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{socket.assigns.current_user.id}:recordings")

      {:ok, _} =
        Presence.track(self(), topic, socket.assigns.current_user.id, %{
          joined_at: System.system_time(:second)
        })
    end

    {:ok,
     socket
     |> assign(:gathering, gathering)
     |> assign(:listener_count, topic |> Presence.list() |> map_size())
     |> assign(:recording, Recordings.active_for(socket.assigns.current_user.id, gathering.id))
     |> assign(:download_url, nil)
     |> assign(:manifest_url, Gatherings.manifest_url(gathering))}
  end

  # ── Events ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("record", _params, socket) do
    {:ok, recording} =
      Recordings.start_recording(socket.assigns.current_user.id, socket.assigns.gathering.id)

    {:noreply, assign(socket, :recording, recording)}
  end

  def handle_event("record_from_start", _params, socket) do
    {:ok, recording} =
      Recordings.record_from_start(socket.assigns.current_user.id, socket.assigns.gathering.id)

    {:noreply, assign(socket, :recording, recording)}
  end

  def handle_event("stop_recording", _params, socket) do
    {:ok, recording} = Recordings.stop_recording(socket.assigns.recording)
    {:noreply, assign(socket, :recording, recording)}
  end

  # ── PubSub ────────────────────────────────────────────────────────────

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    count = "gathering:#{socket.assigns.gathering.id}" |> Presence.list() |> map_size()
    {:noreply, assign(socket, :listener_count, count)}
  end

  def handle_info({:recording_ready, _id, url}, socket) do
    {:noreply,
     socket
     |> assign(:recording, nil)
     |> assign(:download_url, url)
     |> put_flash(:info, "Your recording is ready")}
  end

  def handle_info({:recording_failed, _id}, socket) do
    {:noreply,
     socket
     |> assign(:recording, nil)
     |> put_flash(:error, "Recording failed — please try again")}
  end

  def handle_info({:gathering_ended, _id}, socket) do
    {:noreply, put_flash(socket, :info, "This Gathering has ended")}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Render ────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="gathering">
      <h1>{@gathering.title}</h1>
      <p class="listeners">🎙 {@listener_count} listening</p>

      <audio id="player" phx-hook="HlsPlayer" data-manifest={@manifest_url} controls autoplay />

      <div class="record-controls">
        <%= if @recording do %>
          <button phx-click="stop_recording" class="btn-stop">
            ⏹ Stop &amp; download
          </button>
        <% else %>
          <button phx-click="record" class="btn-record">⏺ Record from now</button>
          <button phx-click="record_from_start" class="btn-record-alt">
            ⏮ Record from the beginning
          </button>
        <% end %>

        <%= if @download_url do %>
          <a href={@download_url} class="btn-download" download>⬇ Download your recording</a>
        <% end %>
      </div>
    </div>
    """
  end
end

# assets/js/hooks/hls_player.js
#
# import Hls from "hls.js";
#
# export const HlsPlayer = {
#   mounted() {
#     const src = this.el.dataset.manifest;
#     if (this.el.canPlayType("application/vnd.apple.mpegurl")) {
#       this.el.src = src;                 // Safari / iOS native HLS
#     } else if (Hls.isSupported()) {
#       this.hls = new Hls({ lowLatencyMode: false });
#       this.hls.loadSource(src);
#       this.hls.attachMedia(this.el);
#     }
#   },
#   destroyed() { this.hls?.destroy(); }
# };
