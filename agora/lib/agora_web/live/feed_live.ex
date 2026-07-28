defmodule AgoraWeb.FeedLive do
  @moduledoc """
  The main feed: posts from everyone the current user clings to, newest
  first, live-updating as new posts land. Uses a LiveView stream so a
  long feed doesn't bloat memory.

  Reaction counts/flags for the whole page load in 2 queries via
  `Posts.reaction_summary_for/2` (see that function) rather than one
  query pair per card, and live in their own `@reactions` map keyed by
  post id so a toggle only touches that one card, not the whole stream.
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
    post_ids = Enum.map(posts, & &1.id)

    {:ok,
     socket
     |> assign(:empty_feed?, posts == [])
     |> assign(:live_now, [])
     |> assign(:reactions, Posts.reaction_summary_for(post_ids, user.id))
     |> stream(:posts, posts)}
  end

  @impl true
  def handle_event("toggle_reaction", %{"kind" => kind, "post_id" => post_id}, socket) do
    user = socket.assigns.current_scope.user
    post_id = String.to_integer(post_id)

    :ok = Posts.toggle_reaction(user.id, post_id, String.to_existing_atom(kind))
    summary = Posts.reaction_summary_for([post_id], user.id)

    # A stream doesn't keep the full collection server-side (that's the
    # whole point — constant memory regardless of feed length), so
    # changing @reactions alone won't touch a card already sent to the
    # client. Re-inserting the same post (matched by id) is how you
    # refresh one stream item in place without duplicating it.
    {:noreply,
     socket
     |> assign(:reactions, Map.merge(socket.assigns.reactions, summary))
     |> stream_insert(:posts, Posts.get_post!(post_id))}
  end

  @impl true
  def handle_info({:new_post, post_id}, socket) do
    post = Posts.get_post!(post_id)
    user = socket.assigns.current_scope.user
    summary = Posts.reaction_summary_for([post_id], user.id)

    {:noreply,
     socket
     |> assign(:empty_feed?, false)
     |> assign(:reactions, Map.merge(socket.assigns.reactions, summary))
     |> stream_insert(:posts, post, at: 0)}
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
      <h1 class="flex items-center gap-2 text-xl font-bold text-base-content px-4 pt-2 pb-4 rise-in">
        <.icon name="hero-sparkles" class="size-5 text-primary" /> Feed
      </h1>

      <div :if={@live_now != []} class="px-4 pb-4 space-y-2">
        <.link
          :for={banner <- @live_now}
          navigate={~p"/gatherings/#{banner.id}"}
          class="flex items-center gap-2 rounded-lg bg-primary depth-glow px-4 py-3 text-white
                 transition-all duration-200 hover:bg-primary/90 hover:-translate-y-0.5 rise-in"
        >
          <.icon name="hero-signal" class="size-5 shrink-0 motion-safe:animate-pulse" />
          <span class="text-sm font-medium">
            {banner.broadcaster_name} is live now — {banner.title}
          </span>
        </.link>
      </div>

      <div id="feed" phx-update="stream" class="flex flex-col gap-3 px-4">
        <div :for={{dom_id, post} <- @streams.posts} id={dom_id}>
          <.feed_card
            post={post}
            navigate={~p"/posts/#{post.id}"}
            reactions={
              @reactions[post.id] ||
                %{heart_count: 0, torch_count: 0, hearted?: false, torched?: false}
            }
          />
        </div>
      </div>

      <div :if={@empty_feed?} class="flex flex-col items-center gap-3 px-4 py-16 text-center rise-in">
        <div class="flex items-center justify-center size-16 rounded-full glass depth-card text-primary">
          <.icon name="hero-user-group" class="size-8" />
        </div>
        <p class="text-base-content font-medium">Your feed is quiet — for now.</p>
        <p class="text-sm text-base-content/50 max-w-xs">
          Cling to people to see their Tidings, photos, and Gatherings here as they happen.
        </p>
        <.link
          navigate={~p"/profile/#{@current_scope.user.id}"}
          class="btn btn-sm btn-primary active:scale-95 transition-transform mt-2"
        >
          Share a Tiding while you wait
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
