defmodule AgoraWeb.ProfileLive do
  @moduledoc """
  The profile hub — avatar, name, tagline, stats, action row, and (from
  Phase 3 on) the owner's post feed. Bespoke full-bleed chrome, not the
  generic `Layouts.app` navbar — the red header band IS the page's top
  chrome, per the mockup.
  """

  use AgoraWeb, :live_view

  alias Agora.{Accounts, Profiles, Social}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    owner = Accounts.get_user!(id)
    profile = Profiles.get_or_create!(owner)
    viewer = socket.assigns.current_scope && socket.assigns.current_scope.user
    is_owner = !!(viewer && viewer.id == owner.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{owner.id}:stats")
    end

    {:ok,
     socket
     |> assign(:owner, owner)
     |> assign(:profile, profile)
     |> assign(:is_owner, is_owner)
     |> assign_stats(owner.id, viewer)}
  end

  defp assign_stats(socket, owner_id, viewer) do
    socket
    |> assign(:clinger_count, Social.clinger_count(owner_id))
    |> assign(:cling_count, Social.cling_count(owner_id))
    |> assign(:post_count, Profiles.post_count(owner_id))
    |> assign(:gathering_count, Profiles.gathering_count(owner_id))
    |> assign(
      :clinging?,
      !!(viewer && viewer.id != owner_id && Social.clinging?(viewer.id, owner_id))
    )
  end

  @impl true
  def handle_event("cling", _params, socket) do
    case current_viewer(socket) do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      viewer ->
        {:ok, _} = Social.cling(viewer.id, socket.assigns.owner.id)
        {:noreply, assign_stats(socket, socket.assigns.owner.id, viewer)}
    end
  end

  def handle_event("uncling", _params, socket) do
    case current_viewer(socket) do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      viewer ->
        :ok = Social.uncling(viewer.id, socket.assigns.owner.id)
        {:noreply, assign_stats(socket, socket.assigns.owner.id, viewer)}
    end
  end

  def handle_event("coming_soon", %{"feature" => feature}, socket) do
    {:noreply, put_flash(socket, :info, "#{feature} is coming in a later phase.")}
  end

  @impl true
  def handle_info({:stats_updated, _user_id}, socket) do
    {:noreply, assign_stats(socket, socket.assigns.owner.id, current_viewer(socket))}
  end

  defp current_viewer(socket),
    do: socket.assigns.current_scope && socket.assigns.current_scope.user

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <div class="bg-primary px-4 pt-6 pb-4">
        <div class="flex items-start gap-3">
          <.avatar
            avatar_url={@profile.avatar_url}
            display_name={@profile.display_name}
            size="size-16"
          />

          <div class="flex-1 min-w-0 pt-1">
            <h1 class="text-xl font-bold text-white truncate">{@profile.display_name}</h1>
            <p :if={@profile.tagline} class="text-sm text-white/80 truncate">{@profile.tagline}</p>
          </div>

          <div class="flex items-center gap-2 pt-1">
            <button
              :if={!@is_owner}
              type="button"
              phx-click={if @clinging?, do: "uncling", else: "cling"}
              class={[
                "btn btn-sm rounded-full",
                @clinging? && "btn-outline border-white text-white",
                !@clinging? && "bg-black/70 text-white border-none hover:bg-black/90"
              ]}
            >
              {if @clinging?, do: "Clinging", else: "Cling"}
            </button>

            <.link
              :if={@is_owner}
              href={~p"/users/settings"}
              class="btn btn-circle btn-sm btn-ghost text-white"
            >
              <.icon name="hero-cog-6-tooth" class="size-5" />
            </.link>

            <details :if={@is_owner} class="dropdown dropdown-end">
              <summary class="btn btn-circle btn-sm btn-ghost text-white list-none">
                <.icon name="hero-bars-3" class="size-5" />
              </summary>
              <ul class="menu dropdown-content bg-base-200 rounded-box z-10 w-44 p-2 shadow mt-2">
                <li><.link href={~p"/users/settings"}>Settings</.link></li>
                <li><.link href={~p"/users/log-out"} method="delete">Log out</.link></li>
              </ul>
            </details>
          </div>
        </div>

        <div class="grid grid-cols-4 gap-2 mt-5">
          <.action_pill
            icon="hero-microphone"
            label="Start Gathering"
            phx-click="coming_soon"
            phx-value-feature="Gatherings"
          />
          <.action_pill
            icon="hero-photo"
            label="Upload Image"
            phx-click="coming_soon"
            phx-value-feature="Image posts"
          />
          <.action_pill
            icon="hero-megaphone"
            label="Tidings"
            phx-click="coming_soon"
            phx-value-feature="Tidings"
          />
          <.action_pill
            icon="hero-signal"
            label="Join Gathering"
            phx-click="coming_soon"
            phx-value-feature="Gatherings"
          />
        </div>
      </div>

      <div class="grid grid-cols-4 gap-2 py-6 px-4">
        <.stat count={@post_count} label="Posts" />
        <.stat count={@gathering_count} label="Gatherings" />
        <.stat count={@clinger_count} label="Clingers" />
        <.stat count={@cling_count} label="Clings" />
      </div>

      <div class="px-4 py-12 text-center text-base-content/50">
        No posts yet.
      </div>
    </div>

    <Layouts.flash_group flash={@flash} />
    """
  end
end
