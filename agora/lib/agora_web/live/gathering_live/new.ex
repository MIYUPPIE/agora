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

  alias Agora.Gatherings
  alias AgoraWeb.BroadcastChannel

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, gathering: nil, broadcast_token: nil, live?: false)}
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
         |> assign(:broadcast_token, BroadcastChannel.broadcast_token(gathering, user))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Give your Gathering a title.")}
    end
  end

  @impl true
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
      <div class="max-w-lg mx-auto">
        <h1 class="text-xl font-bold text-base-content mb-4">Start a Gathering</h1>

        <div :if={@gathering} class="space-y-6">
          <div
            id="browser-broadcast"
            phx-hook="BrowserBroadcast"
            phx-update="ignore"
            data-gathering-id={@gathering.id}
            data-token={@broadcast_token}
            class="rounded-lg bg-base-200 p-4 space-y-3"
          >
            <p class="text-base-content/80 text-sm">
              Go live right from this device — no extra software needed.
            </p>

            <div data-role="idle" class="space-y-2">
              <button type="button" data-action="start" class="btn btn-primary w-full gap-2">
                <.icon name="hero-microphone" class="size-5" /> Go Live From This Device
              </button>
              <p data-role="unsupported" class="hidden text-xs text-warning">
                Your browser doesn't support broadcasting directly — use the OBS option below instead.
              </p>
            </div>

            <div data-role="live" class="hidden flex items-center justify-between">
              <div class="flex items-center gap-2 text-error">
                <span class="inline-block size-2 rounded-full bg-error animate-pulse"></span>
                <span class="text-sm font-medium">Broadcasting from this device</span>
              </div>
              <button type="button" data-action="stop" class="btn btn-sm btn-outline">
                Stop
              </button>
            </div>

            <p data-role="error" class="hidden text-xs text-error"></p>
          </div>

          <div class="collapse collapse-arrow bg-base-200 rounded-lg">
            <input type="checkbox" />
            <div class="collapse-title text-sm text-base-content/70">
              Broadcasting with OBS or another encoder instead?
            </div>
            <div class="collapse-content space-y-3">
              <p class="text-base-content/80 text-sm">
                Point your encoder at this ingest URL:
              </p>
              <code class="block bg-base-100 p-3 rounded text-sm break-all text-primary">
                {Gatherings.ingest_url(@gathering)}
              </code>
              <p class="text-xs text-base-content/50">
                Set your encoder's audio bitrate to 48–64 kbps AAC-HE (voice) — it
                costs your listeners far less data and rarely matters for speech.
                Use 128 kbps only if you're gathering around music.
              </p>
            </div>
          </div>

          <div :if={!@live?} class="flex items-center gap-2 text-base-content/60">
            <span class="loading loading-spinner loading-sm"></span>
            <span>Waiting for your broadcast to start…</span>
          </div>

          <div
            :if={@live?}
            class="flex items-center justify-between rounded-lg bg-primary px-4 py-3 text-white"
          >
            <div class="flex items-center gap-2">
              <span class="inline-block size-2 rounded-full bg-white animate-pulse"></span>
              <span class="text-sm font-medium">You're live — listeners can join now</span>
            </div>
            <a
              href={~p"/gatherings/#{@gathering.id}"}
              target="_blank"
              class="btn btn-xs bg-black/70 text-white border-none hover:bg-black/90"
            >
              View as a listener
            </a>
          </div>
        </div>

        <form :if={!@gathering} phx-submit="create" class="space-y-4">
          <input
            type="text"
            name="gathering[title]"
            placeholder="What are we gathering for?"
            class="input w-full"
            required
          />
          <button type="submit" class="btn btn-primary w-full">Start Gathering</button>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
