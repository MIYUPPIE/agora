defmodule AgoraWeb.GatheringLive.New do
  @moduledoc """
  "Start Gathering" — creates a scheduled Gathering, then offers two ways
  to actually broadcast: straight from this device's mic (the
  BrowserBroadcast hook + AgoraWeb.BroadcastChannel), or the ingest URL
  for OBS/an external encoder.

  This page deliberately does NOT auto-navigate the broadcaster away once
  the Gathering flips live. That's safe for OBS (the encoder is a
  separate process outside the browser), but for a browser broadcast the
  *tab itself* is the encoder — `push_navigate`-ing away tears down the
  BrowserBroadcast hook's DOM and, with it, the live MediaRecorder/mic
  stream. Confirmed hands-on: the old auto-navigate made a browser
  broadcast go live and die in the same second every time. Instead this
  page just flips a banner in place; viewing as a listener is an
  explicit, new-tab link so the broadcasting tab is never disturbed.
  """

  use AgoraWeb, :live_view

  alias Agora.{Gatherings, Profiles}
  alias Agora.Media.AudioEffects
  alias AgoraWeb.BroadcastChannel

  @max_chat_messages 50

  @impl true
  def mount(_params, _session, socket) do
    broadcaster_profile = Profiles.get_or_create!(socket.assigns.current_scope.user)

    {:ok,
     assign(socket,
       gathering: nil,
       broadcast_token: nil,
       live?: false,
       effect_params: nil,
       broadcaster_profile: broadcaster_profile,
       chat_messages: [],
       chat_draft: ""
     )}
  end

  @impl true
  def handle_event("create", %{"gathering" => %{"title" => title}}, socket) do
    user = socket.assigns.current_scope.user

    case Gatherings.create_gathering(user.id, %{"title" => title}) do
      {:ok, gathering} ->
        Phoenix.PubSub.subscribe(Agora.PubSub, "gathering:#{gathering.id}")

        {:noreply,
         socket
         |> assign(:gathering, gathering)
         |> assign(:broadcast_token, BroadcastChannel.broadcast_token(gathering, user))
         |> assign(:effect_params, AudioEffects.get_params(user.id))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Give your Gathering a title.")}
    end
  end

  def handle_event("update_effect", changes, socket) do
    user = socket.assigns.current_scope.user
    gathering = socket.assigns.gathering

    case AudioEffects.update_params(gathering.id, user.id, changes) do
      {:ok, params} -> {:noreply, assign(socket, :effect_params, params)}
      {:error, _changeset} -> {:noreply, socket}
    end
  end

  def handle_event("send_chat", %{"body" => body}, socket) do
    body = String.trim(body)

    if body != "" and socket.assigns.gathering do
      message = %{display_name: socket.assigns.broadcaster_profile.display_name, body: body}

      Phoenix.PubSub.broadcast(
        Agora.PubSub,
        "gathering:#{socket.assigns.gathering.id}",
        {:chat_message, message}
      )
    end

    {:noreply, assign(socket, :chat_draft, "")}
  end

  @impl true
  def handle_info({:chat_message, message}, socket) do
    messages = [message | socket.assigns.chat_messages] |> Enum.take(@max_chat_messages)
    {:noreply, assign(socket, :chat_messages, messages)}
  end

  def handle_info({:gathering_live, id}, socket) do
    if socket.assigns.gathering && socket.assigns.gathering.id == id do
      {:noreply, assign(socket, :live?, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:gathering_ended, id}, socket) do
    if socket.assigns.gathering && socket.assigns.gathering.id == id do
      {:noreply, assign(socket, :live?, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-xl mx-auto py-2 font-sans">
        <!-- Title Header -->
        <div class="flex items-center gap-3 mb-5">
          <div class="flex items-center justify-center size-9 rounded-xl bg-primary/10 text-primary">
            <.icon name="hero-microphone" class="size-5" />
          </div>
          <div>
            <h1 class="font-display text-xl font-bold text-base-content tracking-wide">
              Broadcast Studio
            </h1>
            <p class="text-xs text-base-content/50">Configure &amp; launch your live audio room</p>
          </div>
        </div>

        <!-- Initial Setup Form Card -->
        <form
          :if={!@gathering}
          class="rounded-2xl bg-base-200/60 border border-base-content/[0.06] p-6 space-y-4"
          phx-submit="create"
        >
          <div class="border-b border-base-content/[0.06] pb-3">
            <h3 class="font-display text-base font-bold text-base-content">Create New Broadcast</h3>
            <p class="text-xs text-base-content/50 mt-0.5">
              Give your live audio gathering a title to generate ingest credentials
            </p>
          </div>

          <div class="space-y-1.5">
            <label class="text-xs font-bold uppercase tracking-wider text-base-content/70">Gathering Title</label>
            <input
              type="text"
              name="gathering[title]"
              placeholder="What topic are we gathering for today?"
              class="input w-full well border-base-content/10 text-base-content placeholder:text-base-content/30 focus:border-primary focus:ring-1 focus:ring-primary h-11 text-sm rounded-xl"
              required
            />
          </div>

          <button
            type="submit"
            class="btn btn-primary font-bold text-xs active:scale-95 transition-all w-full h-11 rounded-xl"
          >
            <.icon name="hero-sparkles" class="size-4" /> Initialize Gathering Studio
          </button>
        </form>

        <div :if={@gathering} class="space-y-4">
          <!-- Browser Broadcast Control Box -->
          <div
            id="browser-broadcast"
            phx-hook="BrowserBroadcast"
            phx-update="ignore"
            data-gathering-id={@gathering.id}
            data-token={@broadcast_token}
            class="rounded-2xl bg-base-200/60 border border-base-content/[0.06] p-5 space-y-4"
          >
            <div class="flex items-center justify-between border-b border-base-content/[0.06] pb-3">
              <div>
                <h3 class="font-display text-base font-bold text-base-content">
                  Browser Microphone Studio
                </h3>
                <p class="text-xs text-base-content/50">
                  Broadcast directly from this device's microphone
                </p>
              </div>
              <span class="px-2.5 py-1 rounded-full bg-base-content/[0.05] text-[10px] font-mono text-base-content/60 border border-base-content/[0.06]">
                WebRTC Ingest
              </span>
            </div>

            <div data-role="idle" class="space-y-3">
              <button
                type="button"
                data-action="start"
                class="btn btn-primary btn-lg w-full font-bold text-white shadow active:scale-95 transition-all gap-2 rounded-xl"
              >
                <.icon name="hero-microphone" class="size-6" /> Go Live From This Device
              </button>
              <p
                data-role="unsupported"
                class="hidden text-xs text-warning bg-warning/10 p-2.5 rounded-lg border border-warning/20"
              >
                Your browser doesn't support WebRTC broadcasting — use the OBS option below.
              </p>
            </div>

            <div
              data-role="live"
              class="hidden flex items-center justify-between bg-primary/10 p-4 rounded-xl border border-primary/20"
            >
              <div class="flex items-center gap-2.5 text-primary">
                <span class="inline-block size-3 rounded-full bg-primary motion-safe:animate-ping"></span>
                <span class="text-sm font-bold">Broadcasting from this device</span>
              </div>
              <button
                type="button"
                data-action="stop"
                class="btn btn-sm btn-error font-bold text-xs active:scale-95 transition-all"
              >
                Stop
              </button>
            </div>

            <p
              data-role="error"
              class="hidden text-xs text-error bg-error/10 p-2.5 rounded-lg border border-error/20"
            >
            </p>
          </div>

          <!-- OBS RTMP Accordion -->
          <div class="collapse collapse-arrow bg-base-200/60 border border-base-content/[0.06] rounded-2xl">
            <input type="checkbox" />
            <div class="collapse-title text-sm font-bold text-base-content/90 flex items-center gap-2">
              <.icon name="hero-video-camera" class="size-4 text-primary" />
              Use External Encoder (OBS / Streamlabs RTMP)
            </div>
            <div class="collapse-content space-y-3 pt-2">
              <p class="text-xs text-base-content/60">
                Point your streaming encoder (OBS, Audio Hijack, or hardware mixer) to this RTMP Ingest URL:
              </p>
              <div class="relative group">
                <code class="block well p-3.5 rounded-xl text-xs font-mono break-all text-primary border border-primary/20">
                  {Gatherings.ingest_url(@gathering)}
                </code>
              </div>
              <div class="p-3 rounded-xl bg-base-content/[0.03] border border-base-content/[0.04] space-y-1">
                <p class="text-[11px] font-bold text-base-content">Recommended Audio Bitrate:</p>
                <p class="text-[11px] text-base-content/50 leading-relaxed">
                  Set audio bitrate to <strong class="text-primary">48–64 kbps AAC-HE</strong>
                  for speech. This drastically minimizes data usage for mobile listeners without sacrificing voice clarity.
                </p>
              </div>
            </div>
          </div>

          <.effects_panel params={@effect_params} />

          <!-- Live Status Banner -->
          <div
            :if={!@live?}
            class="flex items-center justify-center gap-2.5 p-4 rounded-xl bg-base-200/40 text-xs text-base-content/60 border border-base-content/[0.04]"
          >
            <span class="loading loading-spinner loading-xs text-primary"></span>
            <span>Waiting for your broadcast to start…</span>
          </div>

          <div
            :if={@live?}
            class="flex items-center justify-between rounded-2xl bg-gradient-to-r from-primary to-rose-600 p-4 text-white shadow"
          >
            <div class="flex items-center gap-2.5">
              <span class="inline-block size-3 rounded-full bg-white motion-safe:animate-ping"></span>
              <span class="text-sm font-bold">You're live — listeners can join now</span>
            </div>
            <a
              href={~p"/gatherings/#{@gathering.id}"}
              target="_blank"
              class="btn btn-sm bg-black/60 text-white border-none hover:bg-black/80 font-bold text-xs active:scale-95 transition-all shadow"
            >
              <.icon name="hero-arrow-top-right-on-square" class="size-4" /> View as a listener
            </a>
          </div>

          <.chat_panel messages={@chat_messages} draft={@chat_draft} />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
