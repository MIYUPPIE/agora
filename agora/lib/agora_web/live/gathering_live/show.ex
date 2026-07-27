defmodule AgoraWeb.GatheringLive.Show do
  @moduledoc """
  Listener view of a live Gathering: HLS player, live listener count via
  Presence, the Record -> Stop -> Download flow, and in-Gathering chat
  (ephemeral — no persistence, just PubSub on the same `gathering:<id>`
  topic used for lifecycle events).

  The player itself is a tiny JS hook using hls.js (vendored, ESM) —
  LiveView owns all state, the hook only attaches the manifest URL to
  an <audio> element.
  """

  use AgoraWeb, :live_view

  alias Agora.{Gatherings, Media, Profiles, Recordings}
  alias AgoraWeb.Presence

  @segment_duration_s 4
  @max_chat_messages 50

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    gathering = Gatherings.get!(id)
    topic = "gathering:#{gathering.id}"
    user = socket.assigns.current_scope.user
    viewer_profile = Profiles.get_or_create!(user)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Agora.PubSub, topic)
      Phoenix.PubSub.subscribe(Agora.PubSub, "#{topic}:segments")
      Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{user.id}:recordings")

      {:ok, _} =
        Presence.track(self(), topic, user.id, %{
          joined_at: System.system_time(:second)
        })
    end

    {:ok,
     socket
     |> assign(:gathering, gathering)
     |> assign(:viewer_profile, viewer_profile)
     |> assign(:listener_count, topic |> Presence.list() |> map_size())
     |> assign(:recording, Recordings.active_for(user.id, gathering.id))
     |> assign(:head_sequence, Media.current_sequence(gathering.id))
     |> assign(:download_url, nil)
     |> assign(:chat_messages, [])
     |> assign(:chat_draft, "")
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

  def handle_event("send_chat", %{"body" => body}, socket) do
    body = String.trim(body)

    if body != "" do
      message = %{display_name: socket.assigns.viewer_profile.display_name, body: body}

      Phoenix.PubSub.broadcast(
        Agora.PubSub,
        "gathering:#{socket.assigns.gathering.id}",
        {:chat_message, message}
      )
    end

    {:noreply, assign(socket, :chat_draft, "")}
  end

  # ── PubSub ────────────────────────────────────────────────────────────

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    count = "gathering:#{socket.assigns.gathering.id}" |> Presence.list() |> map_size()
    {:noreply, assign(socket, :listener_count, count)}
  end

  def handle_info({:segment, seq}, socket) do
    {:noreply, assign(socket, :head_sequence, seq)}
  end

  def handle_info({:chat_message, message}, socket) do
    messages = [message | socket.assigns.chat_messages] |> Enum.take(@max_chat_messages)
    {:noreply, assign(socket, :chat_messages, messages)}
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

  defp recording_elapsed_s(%{start_seq: start_seq}, head_sequence) do
    max(head_sequence - start_seq, 0) * @segment_duration_s
  end

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

      <div class="flex flex-wrap items-center gap-2 mt-6">
        <%= if @recording do %>
          <button phx-click="stop_recording" class="btn btn-error">
            ⏹ Stop &amp; download
          </button>
          <span class="text-sm text-base-content/60">
            Recording — {recording_elapsed_s(@recording, @head_sequence)}s
          </span>
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

      <div class="mt-8">
        <h2 class="text-sm font-semibold text-base-content/70 mb-2">Chat</h2>
        <div
          id="chat-messages"
          class="h-48 overflow-y-auto rounded-lg bg-base-200 p-3 space-y-1 mb-2 flex flex-col-reverse"
        >
          <div :for={message <- @chat_messages} class="text-sm">
            <span class="font-semibold text-primary">{message.display_name}</span>
            <span class="text-base-content/80">{message.body}</span>
          </div>
        </div>
        <form phx-submit="send_chat" class="flex gap-2">
          <input
            type="text"
            name="body"
            value={@chat_draft}
            placeholder="Say something…"
            autocomplete="off"
            class="input input-sm flex-1"
          />
          <button type="submit" class="btn btn-sm btn-primary">Send</button>
        </form>
      </div>
    </div>
    """
  end
end
