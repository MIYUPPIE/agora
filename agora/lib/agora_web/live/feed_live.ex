defmodule AgoraWeb.FeedLive do
  @moduledoc """
  The main feed: posts from everyone the current user clings to, newest
  first, live-updating as new posts land. Uses a LiveView stream so a
  long feed doesn't bloat memory.
  """

  use AgoraWeb, :live_view

  alias Agora.Posts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Agora.PubSub, "feed:#{user.id}")
      Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{user.id}:notifications")
    end

    posts = Posts.list_feed_for(user.id)

    {:ok,
     socket
     |> assign(:empty_feed?, posts == [])
     |> assign(:live_now, [])
     |> stream(:posts, posts)}
  end

  @impl true
  def handle_info({:new_post, post_id}, socket) do
    {:noreply,
     socket
     |> assign(:empty_feed?, false)
     |> stream_insert(:posts, Posts.get_post!(post_id), at: 0)}
  end

  def handle_info({:gathering_live_notification, gathering_id, broadcaster_name, title}, socket) do
    banner = %{id: gathering_id, broadcaster_name: broadcaster_name, title: title}
    {:noreply, assign(socket, :live_now, [banner | socket.assigns.live_now])}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-xl font-bold text-base-content px-4 pt-2 pb-4">Feed</h1>

      <div :if={@live_now != []} class="px-4 pb-4 space-y-2">
        <.link
          :for={banner <- @live_now}
          navigate={~p"/gatherings/#{banner.id}"}
          class="flex items-center gap-2 rounded-lg bg-primary px-4 py-3 text-white hover:bg-primary/90 transition-colors"
        >
          <.icon name="hero-signal" class="size-5 shrink-0" />
          <span class="text-sm font-medium">
            {banner.broadcaster_name} is live now — {banner.title}
          </span>
        </.link>
      </div>

      <div id="feed" phx-update="stream" class="divide-y divide-base-300">
        <div :for={{dom_id, post} <- @streams.posts} id={dom_id}>
          <.post_row post={post} navigate={~p"/posts/#{post.id}"} />
        </div>
      </div>

      <p :if={@empty_feed?} class="px-4 py-12 text-center text-base-content/50">
        No posts yet — cling to someone to see their posts here.
      </p>
    </Layouts.app>
    """
  end
end
