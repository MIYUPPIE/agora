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

  It's also resumable: `mount/3` always checks
  `Gatherings.get_active_for_user/1` first and, if the broadcaster
  already has a `:scheduled` or `:live` Gathering, drops them straight
  back into that Studio session instead of a blank "create" form. OBS's
  RTMP connection lives entirely server-side and doesn't care whether
  this LiveView is even connected — without this, refreshing the tab
  (or losing it — a crash, an accidental close) after pointing OBS at
  the ingest URL would silently keep broadcasting while the broadcaster
  lost every control over it, and submitting the create form again
  would mint a second, unrelated Gathering with its own stream key
  rather than getting back to the first.
  """

  use AgoraWeb, :live_view

  alias Agora.{Gatherings, Profiles, Transcripts}
  alias Agora.Media.{AudioEffects, GatheringPipeline, Transcription}
  alias AgoraWeb.BroadcastChannel

  @max_chat_messages 50
  @max_transcript_segments 100

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    broadcaster_profile = Profiles.get_or_create!(user)
    socket = assign(socket, broadcaster_profile: broadcaster_profile)

    # Resume straight into an existing scheduled/live Gathering rather than
    # showing a blank "create" form — see get_active_for_user/1's moduledoc.
    # This makes a page refresh (or reopening the tab) safe at any point
    # during a broadcast, OBS included, since OBS's connection to the RTMP
    # ingest is entirely independent of this LiveView process.
    case Gatherings.get_active_for_user(user.id) do
      nil ->
        {:ok,
         assign(socket,
           gathering: nil,
           broadcast_token: nil,
           live?: false,
           gathering_ended?: false,
           effect_params: nil,
           chat_messages: [],
           chat_draft: "",
           transcript_segments: [],
           transcript_finalized: false,
           transcription_enabled: true
         )}

      gathering ->
        {:ok, resume(socket, gathering, user)}
    end
  end

  defp resume(socket, gathering, user) do
    Phoenix.PubSub.subscribe(Agora.PubSub, "gathering:#{gathering.id}")
    Phoenix.PubSub.subscribe(Agora.PubSub, "gathering:#{gathering.id}:transcript")

    transcript_segments =
      Transcripts.list_for_gathering(gathering.id)
      |> Enum.take(-@max_transcript_segments)
      |> Enum.reverse()

    assign(socket,
      gathering: gathering,
      broadcast_token: BroadcastChannel.broadcast_token(gathering, user),
      live?: gathering.status == :live,
      gathering_ended?: false,
      effect_params: AudioEffects.get_params(user.id),
      chat_messages: [],
      chat_draft: "",
      transcript_segments: transcript_segments,
      transcript_finalized: Transcripts.finalized?(gathering.id),
      transcription_enabled: true
    )
  end

  @impl true
  def handle_event("create", %{"gathering" => %{"title" => title}}, socket) do
    user = socket.assigns.current_scope.user

    case Gatherings.create_gathering(user.id, %{"title" => title}) do
      {:ok, gathering} ->
        Phoenix.PubSub.subscribe(Agora.PubSub, "gathering:#{gathering.id}")
        Phoenix.PubSub.subscribe(Agora.PubSub, "gathering:#{gathering.id}:transcript")

        {:noreply,
         socket
         |> assign(:gathering, gathering)
         |> assign(:broadcast_token, BroadcastChannel.broadcast_token(gathering, user))
         |> assign(:gathering_ended?, false)
         |> assign(:effect_params, AudioEffects.get_params(user.id))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Give your Gathering a title.")}
    end
  end

  # The broadcaster's "End Gathering" button — works regardless of how
  # they're connected (OBS/RTMP directly, or the browser-mic bridge) and
  # regardless of which device/tab is doing the asking; see
  # GatheringPipeline.stop/1's moduledoc. The UI itself updates via the
  # same {:gathering_ended, id} PubSub message a natural disconnect sends
  # (handled below), not directly here.
  def handle_event("stop_broadcast", _params, socket) do
    GatheringPipeline.stop(socket.assigns.gathering.id)
    {:noreply, socket}
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

  def handle_event("toggle_captions", _params, socket) do
    enabled? = !socket.assigns.transcription_enabled
    Transcription.set_enabled(socket.assigns.gathering.id, enabled?)
    {:noreply, assign(socket, :transcription_enabled, enabled?)}
  end

  @impl true
  def handle_info({:chat_message, message}, socket) do
    messages = [message | socket.assigns.chat_messages] |> Enum.take(@max_chat_messages)
    {:noreply, assign(socket, :chat_messages, messages)}
  end

  def handle_info({:transcript_segment, segment}, socket) do
    segments =
      [segment | socket.assigns.transcript_segments] |> Enum.take(@max_transcript_segments)

    {:noreply, assign(socket, :transcript_segments, segments)}
  end

  def handle_info({:transcript_finalized, _id}, socket) do
    gathering_id = socket.assigns.gathering.id
    segments = Transcripts.list_for_gathering(gathering_id)

    {:noreply,
     socket
     |> assign(
       :transcript_segments,
       segments |> Enum.take(-@max_transcript_segments) |> Enum.reverse()
     )
     |> assign(:transcript_finalized, true)}
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
      {:noreply, assign(socket, live?: false, gathering_ended?: true)}
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
                OBS and Streamlabs ask for a <strong>Server</strong>
                and a <strong>Stream Key</strong> as two separate fields — paste each one into its matching field below. Do not paste the combined URL into the "Server" field alone, and leave "Stream Key" blank — that sends your key as part of the server address instead, which the server can't match and your connection will be rejected.
              </p>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div class="space-y-1">
                  <p class="text-[11px] font-bold text-base-content/70 uppercase tracking-wide">Server</p>
                  <div
                    id="server-url-copy"
                    phx-hook="CopyToClipboard"
                    phx-update="ignore"
                    class="relative group cursor-pointer"
                    title="Copy server URL"
                  >
                    <code
                      data-role="ingest-url"
                      class="block well p-3.5 pr-11 rounded-xl text-xs font-mono break-all text-primary border border-primary/20"
                    >
                      {Gatherings.server_url()}
                    </code>
                    <span
                      data-role="idle"
                      class="absolute top-2.5 right-2.5 flex items-center justify-center size-7 rounded-lg bg-base-content/[0.06] text-base-content/50 group-hover:text-primary group-hover:bg-primary/10 transition-colors"
                    >
                      <.icon name="hero-clipboard-document" class="size-4" />
                    </span>
                    <span
                      data-role="copied"
                      class="hidden absolute top-2.5 right-2.5 flex items-center justify-center size-7 rounded-lg bg-emerald-400/10 text-emerald-400"
                    >
                      <.icon name="hero-check" class="size-4" />
                    </span>
                  </div>
                </div>
                <div class="space-y-1">
                  <p class="text-[11px] font-bold text-base-content/70 uppercase tracking-wide">Stream Key</p>
                  <div
                    id="stream-key-copy"
                    phx-hook="CopyToClipboard"
                    phx-update="ignore"
                    class="relative group cursor-pointer"
                    title="Copy stream key"
                  >
                    <code
                      data-role="ingest-url"
                      class="block well p-3.5 pr-11 rounded-xl text-xs font-mono break-all text-primary border border-primary/20"
                    >
                      {@gathering.stream_key}
                    </code>
                    <span
                      data-role="idle"
                      class="absolute top-2.5 right-2.5 flex items-center justify-center size-7 rounded-lg bg-base-content/[0.06] text-base-content/50 group-hover:text-primary group-hover:bg-primary/10 transition-colors"
                    >
                      <.icon name="hero-clipboard-document" class="size-4" />
                    </span>
                    <span
                      data-role="copied"
                      class="hidden absolute top-2.5 right-2.5 flex items-center justify-center size-7 rounded-lg bg-emerald-400/10 text-emerald-400"
                    >
                      <.icon name="hero-check" class="size-4" />
                    </span>
                  </div>
                </div>
              </div>
              <p class="text-xs text-base-content/60 pt-1">
                Encoders that only take a single field (ffmpeg, hardware mixers, Audio Hijack) can use this combined ingest URL instead:
              </p>
              <div
                id="ingest-url-copy"
                phx-hook="CopyToClipboard"
                phx-update="ignore"
                class="relative group cursor-pointer"
                title="Copy ingest URL"
              >
                <code
                  data-role="ingest-url"
                  class="block well p-3.5 pr-11 rounded-xl text-xs font-mono break-all text-primary border border-primary/20"
                >
                  {Gatherings.ingest_url(@gathering)}
                </code>
                <span
                  data-role="idle"
                  class="absolute top-2.5 right-2.5 flex items-center justify-center size-7 rounded-lg bg-base-content/[0.06] text-base-content/50 group-hover:text-primary group-hover:bg-primary/10 transition-colors"
                >
                  <.icon name="hero-clipboard-document" class="size-4" />
                </span>
                <span
                  data-role="copied"
                  class="hidden absolute top-2.5 right-2.5 flex items-center justify-center size-7 rounded-lg bg-emerald-400/10 text-emerald-400"
                >
                  <.icon name="hero-check" class="size-4" />
                </span>
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

          <button
            :if={!@gathering_ended?}
            type="button"
            phx-click="stop_broadcast"
            phx-disable-with="Ending…"
            data-confirm="End this Gathering now? Your OBS/encoder connection will be dropped and listeners disconnected."
            class="btn btn-sm btn-ghost text-error/70 hover:text-error hover:bg-error/10 font-bold text-xs w-full active:scale-95 transition-all rounded-xl"
          >
            <.icon name="hero-stop-circle" class="size-4" /> End Gathering
          </button>

          <.transcript_panel
            segments={@transcript_segments}
            gathering_id={@gathering.id}
            finalized={@transcript_finalized}
            show_toggle={true}
            enabled={@transcription_enabled}
          />

          <.chat_panel messages={@chat_messages} draft={@chat_draft} />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
