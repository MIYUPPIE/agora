defmodule AgoraWeb.ClingsLive do
  @moduledoc """
  The Clingers (followers) / Clings (following) list for a profile — two
  tabs over the same follow graph `Agora.Social` already exposes via the
  profile hub's stat pills. Each row carries its own Cling/Clinging
  button so a visitor can follow someone straight from the list without
  first opening their profile.
  """

  use AgoraWeb, :live_view

  alias Agora.{Accounts, Profiles, Social}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    owner = Accounts.get_user!(id)
    profile = Profiles.get_or_create!(owner)

    {:ok,
     socket
     |> assign(:owner, owner)
     |> assign(:profile, profile)
     |> assign(:clinger_count, Social.clinger_count(owner.id))
     |> assign(:cling_count, Social.cling_count(owner.id))}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    kind = if socket.assigns.live_action == :clingers, do: :clingers, else: :clings
    {:noreply, socket |> assign(:kind, kind) |> assign_people()}
  end

  defp assign_people(socket) do
    owner_id = socket.assigns.owner.id
    viewer = current_viewer(socket)

    people =
      case socket.assigns.kind do
        :clingers -> Social.list_clingers(owner_id)
        :clings -> Social.list_clings(owner_id)
      end

    clinging_set = Social.clinging_set(viewer && viewer.id, Enum.map(people, & &1.id))

    socket
    |> assign(:people, people)
    |> assign(:clinging_set, clinging_set)
  end

  @impl true
  def handle_event("cling", %{"user_id" => user_id}, socket) do
    case current_viewer(socket) do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      viewer ->
        {:ok, _} = Social.cling(viewer.id, user_id)

        {:noreply,
         socket
         |> update(:clinging_set, &MapSet.put(&1, user_id))
         |> maybe_bump_clinger_count(user_id, +1)}
    end
  end

  def handle_event("uncling", %{"user_id" => user_id}, socket) do
    case current_viewer(socket) do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      viewer ->
        :ok = Social.uncling(viewer.id, user_id)

        {:noreply,
         socket
         |> update(:clinging_set, &MapSet.delete(&1, user_id))
         |> maybe_bump_clinger_count(user_id, -1)}
    end
  end

  defp maybe_bump_clinger_count(socket, user_id, delta) do
    if user_id == socket.assigns.owner.id do
      update(socket, :clinger_count, &(&1 + delta))
    else
      socket
    end
  end

  defp current_viewer(socket),
    do: socket.assigns.current_scope && socket.assigns.current_scope.user

  defp viewer(assigns), do: assigns.current_scope && assigns.current_scope.user

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-2xl mx-auto space-y-4">
        <!-- Header -->
        <div class="flex items-center gap-3 px-1">
          <.link
            navigate={~p"/profile/#{@owner.id}"}
            class="flex items-center justify-center size-9 rounded-xl bg-base-content/[0.04] hover:bg-base-content/[0.08] text-base-content/70 hover:text-base-content transition-all shrink-0"
          >
            <.icon name="hero-arrow-left" class="size-4" />
          </.link>
          <div class="flex items-center gap-2.5 min-w-0">
            <.avatar
              avatar_url={@profile.avatar_url}
              display_name={@profile.display_name}
              size="size-9"
            />
            <div class="min-w-0">
              <h1 class="font-display text-base font-bold text-base-content truncate">
                {@profile.display_name}
              </h1>
              <p class="text-xs text-base-content/50">Clingers &amp; Clings</p>
            </div>
          </div>
        </div>

        <!-- Tabs -->
        <div class="grid grid-cols-2 gap-2 p-1.5 rounded-2xl bg-base-content/[0.04] border border-base-content/[0.06]">
          <.link
            patch={~p"/profile/#{@owner.id}/clingers"}
            class={[
              "rounded-xl py-2.5 text-center text-sm font-bold transition-all",
              @kind == :clingers && "bg-primary text-white shadow",
              @kind != :clingers &&
                "text-base-content/60 hover:text-base-content hover:bg-base-content/[0.06]"
            ]}
          >
            {@clinger_count} Clingers
          </.link>
          <.link
            patch={~p"/profile/#{@owner.id}/clings"}
            class={[
              "rounded-xl py-2.5 text-center text-sm font-bold transition-all",
              @kind == :clings && "bg-primary text-white shadow",
              @kind != :clings &&
                "text-base-content/60 hover:text-base-content hover:bg-base-content/[0.06]"
            ]}
          >
            {@cling_count} Clings
          </.link>
        </div>

        <!-- People List -->
        <div :if={@people != []} class="flex flex-col gap-2">
          <div
            :for={person <- @people}
            class="flex items-center gap-3 px-4 py-3 rounded-2xl bg-base-content/[0.03] hover:bg-base-content/[0.06] border border-base-content/[0.04] transition-all"
          >
            <.link
              navigate={~p"/profile/#{person.id}"}
              class="flex items-center gap-3 flex-1 min-w-0 group"
            >
              <.avatar
                avatar_url={person.profile.avatar_url}
                display_name={person.profile.display_name}
                size="size-11"
              />
              <div class="min-w-0">
                <p class="text-sm font-bold text-base-content group-hover:text-primary transition-colors truncate">
                  {person.profile.display_name}
                </p>
                <p
                  :if={person.profile.tagline not in [nil, ""]}
                  class="text-xs text-base-content/50 truncate"
                >
                  {person.profile.tagline}
                </p>
              </div>
            </.link>

            <div :if={!viewer(assigns) || viewer(assigns).id != person.id} class="shrink-0">
              <button
                :if={!MapSet.member?(@clinging_set, person.id)}
                phx-click="cling"
                phx-value-user_id={person.id}
                class="btn btn-primary btn-xs rounded-full font-semibold px-4 active:scale-95 transition-all"
              >
                Cling
              </button>
              <button
                :if={MapSet.member?(@clinging_set, person.id)}
                phx-click="uncling"
                phx-value-user_id={person.id}
                class="btn btn-outline btn-xs rounded-full font-semibold border-base-content/20 hover:bg-base-content/10 text-base-content px-4 active:scale-95 transition-all"
              >
                Clinging
              </button>
            </div>
          </div>
        </div>

        <!-- Empty State -->
        <div :if={@people == []} class="py-16 text-center text-base-content/40 space-y-1">
          <.icon name="hero-user-group" class="size-8 text-base-content/20 mx-auto" />
          <p class="text-sm font-medium">
            {if @kind == :clingers, do: "No Clingers yet.", else: "Not clinging to anyone yet."}
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
