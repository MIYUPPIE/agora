defmodule AgoraWeb.NotificationsLive do
  @moduledoc """
  The notification inbox — clings, comments, reactions, and
  gathering-live events addressed to the current user, newest first.
  Opening the page marks everything read, the same moment the nav
  bell's badge would clear, matching how most social apps treat an
  inbox: unread until seen, not until dismissed one by one.
  """

  use AgoraWeb, :live_view

  alias Agora.Notifications

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{user.id}:notifications")
    end

    Notifications.mark_all_read(user.id)

    {:ok, assign(socket, :notifications, Notifications.list_for_user(user.id))}
  end

  @impl true
  def handle_info({:notification_created, _notification}, socket) do
    user_id = socket.assigns.current_scope.user.id
    Notifications.mark_all_read(user_id)
    {:noreply, assign(socket, :notifications, Notifications.list_for_user(user_id))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-2xl mx-auto space-y-4">
        <div class="flex items-center gap-3 px-1">
          <div class="flex items-center justify-center size-9 rounded-xl bg-primary/10 text-primary shrink-0">
            <.icon name="hero-bell" class="size-5" />
          </div>
          <div>
            <h1 class="font-display text-xl font-bold text-base-content tracking-wide">
              Notifications
            </h1>
            <p class="text-xs text-base-content/50">
              Clings, comments, reactions &amp; live Gatherings
            </p>
          </div>
        </div>

        <div :if={@notifications != []} class="flex flex-col gap-2">
          <.link
            :for={n <- @notifications}
            navigate={notification_target(n)}
            class="flex items-center gap-3 px-4 py-3.5 rounded-2xl bg-base-content/[0.03] hover:bg-base-content/[0.07] border border-base-content/[0.04] transition-all duration-200 active:scale-[0.99] group"
          >
            <.avatar
              :if={n.actor}
              avatar_url={n.actor.profile.avatar_url}
              display_name={n.actor.profile.display_name}
              size="size-10"
            />
            <div
              :if={!n.actor}
              class="flex items-center justify-center size-10 rounded-full bg-primary/10 text-primary shrink-0"
            >
              <.icon name={notification_icon(n)} class="size-5" />
            </div>

            <div class="flex-1 min-w-0">
              <p class="text-sm text-base-content/90 leading-snug">
                <span :if={n.actor} class="font-bold text-base-content">
                  {n.actor.profile.display_name}
                </span>
                {notification_message(n)}
              </p>
              <p class="text-xs text-base-content/40 mt-0.5">{time_ago(n.inserted_at)}</p>
            </div>

            <div class="flex items-center justify-center size-8 rounded-xl bg-base-content/[0.04] text-primary shrink-0">
              <.icon name={notification_icon(n)} class="size-4" />
            </div>
          </.link>
        </div>

        <div :if={@notifications == []} class="py-16 text-center text-base-content/40 space-y-1">
          <.icon name="hero-bell-slash" class="size-8 text-base-content/20 mx-auto" />
          <p class="text-sm font-medium">No notifications yet.</p>
          <p class="text-xs max-w-xs mx-auto leading-relaxed">
            Clings, comments, reactions, and live Gatherings from people you follow will show up here.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp notification_target(%{type: :cling, actor_id: actor_id}), do: ~p"/profile/#{actor_id}"
  defp notification_target(%{type: :comment, post_id: post_id}), do: ~p"/posts/#{post_id}"
  defp notification_target(%{type: :reaction, post_id: post_id}), do: ~p"/posts/#{post_id}"

  defp notification_target(%{type: :gathering_live, gathering_id: gathering_id}),
    do: ~p"/gatherings/#{gathering_id}"

  defp notification_icon(%{type: :cling}), do: "hero-user-plus"
  defp notification_icon(%{type: :comment}), do: "hero-chat-bubble-left"
  defp notification_icon(%{type: :reaction, reaction_kind: :torch}), do: "hero-fire"
  defp notification_icon(%{type: :reaction}), do: "hero-heart"
  defp notification_icon(%{type: :gathering_live}), do: "hero-signal"

  defp notification_message(%{type: :cling}), do: "started clinging to you"
  defp notification_message(%{type: :comment}), do: "commented on your post"
  defp notification_message(%{type: :reaction, reaction_kind: :torch}), do: "torched your post"
  defp notification_message(%{type: :reaction}), do: "hearted your post"
  defp notification_message(%{type: :gathering_live}), do: "is live now"
end
