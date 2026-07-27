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
      <h1 class="text-xl font-bold text-base-content mb-4">Live now</h1>

      <p :if={@gatherings == []} class="text-base-content/50">No one is live right now.</p>

      <div class="divide-y divide-base-300">
        <.link
          :for={gathering <- @gatherings}
          navigate={~p"/gatherings/#{gathering.id}"}
          class="flex items-center gap-3 px-2 py-3 hover:bg-base-200 transition-colors"
        >
          <.avatar
            avatar_url={gathering.user.profile.avatar_url}
            display_name={gathering.user.profile.display_name}
            size="size-10"
          />
          <div>
            <p class="text-base-content font-medium">{gathering.title}</p>
            <p class="text-sm text-base-content/60">{gathering.user.profile.display_name}</p>
          </div>
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
