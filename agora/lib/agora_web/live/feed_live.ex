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
    end

    posts = Posts.list_feed_for(user.id)

    {:ok,
     socket
     |> assign(:empty_feed?, posts == [])
     |> stream(:posts, posts)}
  end

  @impl true
  def handle_info({:new_post, post_id}, socket) do
    {:noreply,
     socket
     |> assign(:empty_feed?, false)
     |> stream_insert(:posts, Posts.get_post!(post_id), at: 0)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-xl font-bold text-base-content px-4 pt-2 pb-4">Feed</h1>

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
