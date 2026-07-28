defmodule AgoraWeb.GatheringLive.Index do
  @moduledoc "Browse Gatherings that are live right now — the 'Join Gathering' destination."

  use AgoraWeb, :live_view

  alias Agora.Gatherings

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :gatherings, Gatherings.list_live())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-xl font-bold text-base-content mb-4 rise-in">Live now</h1>

      <p :if={@gatherings == []} class="text-base-content/50 text-center py-12">
        No one is live right now.
      </p>

      <div class="flex flex-col gap-2">
        <.link
          :for={gathering <- @gatherings}
          navigate={~p"/gatherings/#{gathering.id}"}
          class="flex items-center gap-3 p-3 rounded-box glass depth-card rise-in
                 transition-all duration-200 hover:-translate-y-0.5 hover:bg-white/[0.06] active:scale-[0.99]"
        >
          <div class="relative shrink-0">
            <.avatar
              avatar_url={gathering.user.profile.avatar_url}
              display_name={gathering.user.profile.display_name}
              size="size-10"
            />
            <span class="absolute -bottom-0.5 -right-0.5 size-3 rounded-full bg-primary ring-2 ring-base-100 motion-safe:animate-pulse"></span>
          </div>
          <div class="flex-1 min-w-0">
            <p class="text-base-content font-medium truncate">{gathering.title}</p>
            <p class="text-sm text-base-content/60 truncate">
              {gathering.user.profile.display_name}
            </p>
          </div>
          <span class="shrink-0 badge badge-primary badge-sm gap-1">
            <span class="size-1.5 rounded-full bg-white motion-safe:animate-pulse"></span> LIVE
          </span>
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
