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
    user = socket.assigns.current_scope && socket.assigns.current_scope.user
    viewer_profile = if user, do: Profiles.get_or_create!(user), else: %{display_name: "Listener"}

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Agora.PubSub, topic)
      Phoenix.PubSub.subscribe(Agora.PubSub, "#{topic}:segments")

      if user do
        Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{user.id}:recordings")

        {:ok, _} =
          Presence.track(self(), topic, user.id, %{joined_at: System.system_time(:second)})
      else
        {:ok, _} =
          Presence.track(self(), topic, "anon:#{Ecto.UUID.generate()}", %{
            joined_at: System.system_time(:second)
          })
      end
    end

    recording = if user, do: Recordings.active_for(user.id, gathering.id), else: nil

    {:ok,
     socket
     |> assign(:gathering, gathering)
     |> assign(:viewer_profile, viewer_profile)
     |> assign(:listener_count, topic |> Presence.list() |> map_size())
     |> assign(:recording, recording)
     |> assign(:head_sequence, Media.current_sequence(gathering.id))
     |> assign(:download_url, nil)
     |> assign(:chat_messages, [])
     |> assign(:chat_draft, "")
     |> assign(:manifest_url, Gatherings.manifest_url(gathering))}
  end

  # ── Events ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("record", _params, socket) do
    case socket.assigns.current_scope && socket.assigns.current_scope.user do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      user ->
        {:ok, recording} = Recordings.start_recording(user.id, socket.assigns.gathering.id)
        {:noreply, assign(socket, :recording, recording)}
    end
  end

  def handle_event("record_from_start", _params, socket) do
    case socket.assigns.current_scope && socket.assigns.current_scope.user do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      user ->
        {:ok, recording} = Recordings.record_from_start(user.id, socket.assigns.gathering.id)
        {:noreply, assign(socket, :recording, recording)}
    end
  end

  def handle_event("stop_recording", _params, socket) do
    if socket.assigns.recording do
      {:ok, recording} = Recordings.stop_recording(socket.assigns.recording)
      {:noreply, assign(socket, :recording, recording)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("send_chat", %{"body" => body}, socket) do
    case socket.assigns.current_scope && socket.assigns.current_scope.user do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      _user ->
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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-xl space-y-4 py-2 font-sans">
        <!-- Top Back Navigation -->
        <div class="flex items-center justify-between">
          <.link
            navigate={~p"/gatherings"}
            class="flex items-center gap-2 text-xs font-semibold text-base-content/60 hover:text-base-content transition-colors"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Back to Live Rooms
          </.link>
          <span
            :if={@gathering.status == :live}
            class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-primary/10 text-primary border border-primary/20 text-xs font-extrabold tracking-wider uppercase"
          >
            <span class="size-2 rounded-full bg-primary motion-safe:animate-ping"></span>
            Live Broadcast
          </span>
        </div>

        <!-- Host Banner Card -->
        <div class="flex items-center gap-4 rounded-2xl bg-base-200/60 border border-base-content/[0.06] p-5">
          <div class="relative shrink-0">
            <.avatar
              avatar_url={@gathering.user.profile.avatar_url}
              display_name={@gathering.user.profile.display_name}
              size="size-14"
            />
            <span
              :if={@gathering.status == :live}
              class="absolute -bottom-1 -right-1 flex items-center justify-center size-5 rounded-full bg-primary ring-2 ring-base-100 shadow-md"
            >
              <span class="size-2.5 rounded-full bg-white motion-safe:animate-ping"></span>
            </span>
          </div>

          <div class="flex-1 min-w-0">
            <h1 class="font-display text-lg font-bold text-base-content truncate">
              {@gathering.title}
            </h1>
            <p class="text-xs font-medium text-base-content/50 truncate mt-0.5">
              Host: {@gathering.user.profile.display_name}
            </p>
          </div>

          <div class="shrink-0 text-right">
            <div class="flex items-center gap-1.5 text-xs font-bold text-primary bg-primary/10 px-3 py-1.5 rounded-xl border border-primary/20">
              <.icon name="hero-user-group" class="size-4" />
              <span>{@listener_count} listening</span>
            </div>
          </div>
        </div>

        <!-- Audio Player Stage -->
        <div class="rounded-2xl bg-base-200/60 border border-base-content/[0.06] p-5 space-y-4">
          <div class="flex items-center justify-between text-xs font-bold text-base-content/70">
            <span>Audio Stream Deck</span>
            <span :if={@gathering.status == :live} class="text-emerald-400 flex items-center gap-1.5">
              <span class="size-2 rounded-full bg-emerald-400 motion-safe:animate-pulse"></span>
              Streaming Ready
            </span>
          </div>

          <div class="relative rounded-xl well p-4 border border-base-content/[0.04] flex flex-col items-center justify-center min-h-24">
            <audio
              :if={@gathering.status == :live}
              id="player"
              phx-hook="HlsPlayer"
              phx-update="ignore"
              data-manifest={@manifest_url}
              controls
              autoplay
              class="w-full h-10 accent-primary"
            />
            <p
              :if={@gathering.status != :live}
              class="text-sm font-medium text-base-content/40 py-4 text-center"
            >
              This Gathering isn't live right now.
            </p>
          </div>
        </div>

        <!-- Recording Actions Toolbar -->
        <div class="flex flex-wrap items-center gap-2.5">
          <%= if @recording do %>
            <button
              phx-click="stop_recording"
              class="btn btn-error font-bold text-xs active:scale-95 transition-all shadow-lg"
            >
              <.icon name="hero-stop" class="size-4" /> Stop &amp; download
            </button>
            <span class="text-xs font-mono text-primary font-bold bg-primary/10 px-3 py-2 rounded-xl border border-primary/20">
              Recording — {recording_elapsed_s(@recording, @head_sequence)}s
            </span>
          <% else %>
            <button
              phx-click="record"
              class="btn btn-primary font-bold text-xs active:scale-95 transition-all shadow"
            >
              <.icon name="hero-[hero-record-option]" class="size-4" /> Record from now
            </button>
            <button
              phx-click="record_from_start"
              class="btn btn-outline font-bold text-xs border-base-content/20 hover:bg-base-content/10 active:scale-95 transition-all"
            >
              <.icon name="hero-arrow-uturn-left" class="size-4" /> Record from the beginning
            </button>
          <% end %>

          <%= if @download_url do %>
            <a
              href={@download_url}
              class="btn btn-success font-bold text-xs active:scale-95 transition-all shadow-lg"
              download
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Download your recording
            </a>
          <% end %>
        </div>

        <.chat_panel messages={@chat_messages} draft={@chat_draft} />
      </div>
    </Layouts.app>
    """
  end
end
