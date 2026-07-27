defmodule AgoraWeb.GatheringLive.New do
  @moduledoc """
  "Start Gathering" — creates a scheduled Gathering, shows the
  broadcaster their ingest URL + stream key, and flips to "you're live"
  automatically once their encoder actually connects (the pipeline
  broadcasts on `gathering:<id>` when RTMP ingest starts).
  """

  use AgoraWeb, :live_view

  alias Agora.Gatherings

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, gathering: nil)}
  end

  @impl true
  def handle_event("create", %{"gathering" => %{"title" => title}}, socket) do
    user = socket.assigns.current_scope.user

    case Gatherings.create_gathering(user.id, %{"title" => title}) do
      {:ok, gathering} ->
        Phoenix.PubSub.subscribe(Agora.PubSub, "gathering:#{gathering.id}")
        {:noreply, assign(socket, :gathering, gathering)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Give your Gathering a title.")}
    end
  end

  @impl true
  def handle_info({:gathering_live, id}, socket) do
    if socket.assigns.gathering && socket.assigns.gathering.id == id do
      {:noreply, push_navigate(socket, to: ~p"/gatherings/#{id}")}
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

        <div :if={@gathering} class="space-y-4">
          <p class="text-base-content/80">
            Point your encoder (OBS, mobile app, etc.) at this ingest URL:
          </p>
          <code class="block bg-base-200 p-3 rounded text-sm break-all text-primary">
            {Gatherings.ingest_url(@gathering)}
          </code>
          <div class="flex items-center gap-2 text-base-content/60">
            <span class="loading loading-spinner loading-sm"></span>
            <span>Waiting for your encoder to connect…</span>
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
