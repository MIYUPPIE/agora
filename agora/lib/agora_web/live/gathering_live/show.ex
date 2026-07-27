defmodule AgoraWeb.GatheringLive.Show do
  @moduledoc """
  Listener view of a live Gathering: HLS player, live listener count via
  Presence, and the Record -> Stop -> Download flow.

  The player itself is a tiny JS hook using hls.js (vendored, ESM) —
  LiveView owns all state, the hook only attaches the manifest URL to
  an <audio> element.
  """

  use AgoraWeb, :live_view

  alias Agora.{Gatherings, Recordings}
  alias AgoraWeb.Presence

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    gathering = Gatherings.get!(id)
    topic = "gathering:#{gathering.id}"
    user = socket.assigns.current_scope.user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Agora.PubSub, topic)
      Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{user.id}:recordings")

      {:ok, _} =
        Presence.track(self(), topic, user.id, %{
          joined_at: System.system_time(:second)
        })
    end

    {:ok,
     socket
     |> assign(:gathering, gathering)
     |> assign(:listener_count, topic |> Presence.list() |> map_size())
     |> assign(:recording, Recordings.active_for(user.id, gathering.id))
     |> assign(:download_url, nil)
     |> assign(:manifest_url, Gatherings.manifest_url(gathering))}
  end

  # ── Events ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("record", _params, socket) do
    user = socket.assigns.current_scope.user
    {:ok, recording} = Recordings.start_recording(user.id, socket.assigns.gathering.id)
    {:noreply, assign(socket, :recording, recording)}
  end

  def handle_event("record_from_start", _params, socket) do
    user = socket.assigns.current_scope.user
    {:ok, recording} = Recordings.record_from_start(user.id, socket.assigns.gathering.id)
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

  def handle_info({:gathering_live, _id}, socket) do
    {:noreply,
     socket
     |> assign(:gathering, %{socket.assigns.gathering | status: :live})
     |> put_flash(:info, "This Gathering just went live")}
  end

  def handle_info({:gathering_ended, _id}, socket) do
    {:noreply, put_flash(socket, :info, "This Gathering has ended")}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Render ────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100 px-4 py-6">
      <div class="flex items-center gap-3 mb-4">
        <.avatar
          avatar_url={@gathering.user.profile.avatar_url}
          display_name={@gathering.user.profile.display_name}
          size="size-12"
        />
        <div>
          <h1 class="text-lg font-bold text-base-content">{@gathering.title}</h1>
          <p class="text-sm text-base-content/60">by {@gathering.user.profile.display_name}</p>
        </div>
      </div>

      <p class="text-sm text-primary mb-4">🎙 {@listener_count} listening</p>

      <audio
        :if={@gathering.status == :live}
        id="player"
        phx-hook="HlsPlayer"
        phx-update="ignore"
        data-manifest={@manifest_url}
        controls
        autoplay
        class="w-full"
      />
      <p :if={@gathering.status != :live} class="text-base-content/50">
        This Gathering isn't live right now.
      </p>

      <div class="flex flex-wrap gap-2 mt-6">
        <%= if @recording do %>
          <button phx-click="stop_recording" class="btn btn-error">
            ⏹ Stop &amp; download
          </button>
        <% else %>
          <button phx-click="record" class="btn btn-primary">⏺ Record from now</button>
          <button phx-click="record_from_start" class="btn btn-primary btn-outline">
            ⏮ Record from the beginning
          </button>
        <% end %>

        <%= if @download_url do %>
          <a href={@download_url} class="btn btn-success" download>⬇ Download your recording</a>
        <% end %>
      </div>
    </div>
    """
  end
end
