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
      <!-- Header -->
      <div class="flex items-center justify-between px-2 pt-2 pb-5">
        <div class="flex items-center gap-3">
          <div class="flex items-center justify-center size-9 rounded-xl bg-primary/10 text-primary">
            <.icon name="hero-signal" class="size-5 motion-safe:animate-pulse" />
          </div>
          <div>
            <h1 class="font-display text-xl font-bold text-base-content tracking-wide">
              Live now
            </h1>
            <p class="text-xs text-base-content/50">Tune into live broadcasts happening now</p>
          </div>
        </div>

        <.link
          navigate={~p"/gatherings/new"}
          class="btn btn-primary btn-sm font-bold text-xs text-white active:scale-95 transition-all rounded-full px-4"
        >
          <.icon name="hero-microphone" class="size-4" /> Go Live
        </.link>
      </div>

      <!-- Empty State -->
      <div :if={@gatherings == []} class="flex flex-col items-center gap-4 px-4 py-16 text-center">
        <div class="relative flex items-center justify-center size-16 rounded-2xl bg-base-content/[0.04] text-primary border border-base-content/[0.06]">
          <.icon name="hero-signal-slash" class="size-8" />
        </div>
        <div class="space-y-1">
          <h3 class="font-display text-base font-bold text-base-content">
            No one is live right now.
          </h3>
          <p class="text-xs text-base-content/50 max-w-xs leading-relaxed">
            Be the first to start a Gathering and go live with your voice from your browser!
          </p>
        </div>
        <.link
          navigate={~p"/gatherings/new"}
          class="btn btn-primary btn-sm font-bold text-xs active:scale-95 transition-all mt-2 rounded-full px-5"
        >
          <.icon name="hero-microphone" class="size-4" /> Start Broadcasting
        </.link>
      </div>

      <!-- Live Rooms List -->
      <div class="flex flex-col gap-3 px-2">
        <.link
          :for={gathering <- @gatherings}
          navigate={~p"/gatherings/#{gathering.id}"}
          class="flex items-center gap-4 p-4 rounded-2xl bg-base-200/60 hover:bg-base-200/90 border border-base-content/[0.06]
                 transition-all duration-200 active:scale-[0.99] group"
        >
          <div class="relative shrink-0">
            <.avatar
              avatar_url={gathering.user.profile.avatar_url}
              display_name={gathering.user.profile.display_name}
              size="size-12"
            />
            <span class="absolute -bottom-1 -right-1 flex items-center justify-center size-4 rounded-full bg-primary ring-2 ring-base-100 shadow-md">
              <span class="size-2 rounded-full bg-white motion-safe:animate-ping"></span>
            </span>
          </div>

          <div class="flex-1 min-w-0">
            <h3 class="text-sm font-bold text-base-content group-hover:text-primary transition-colors truncate">
              {gathering.title}
            </h3>
            <p class="text-xs font-medium text-base-content/50 truncate mt-0.5">
              Host: {gathering.user.profile.display_name}
            </p>
          </div>

          <div class="flex items-center gap-2 shrink-0">
            <span class="hidden sm:inline-flex items-center gap-1.5 text-[10px] font-extrabold tracking-wider uppercase px-2.5 py-1 rounded-full bg-primary/10 text-primary border border-primary/20">
              <span class="size-1.5 rounded-full bg-primary motion-safe:animate-ping"></span> LIVE
            </span>
            <span class="btn btn-sm btn-primary font-bold text-xs rounded-full px-4">
              Join
            </span>
          </div>
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
