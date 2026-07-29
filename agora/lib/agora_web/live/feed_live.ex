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
    user = socket.assigns.current_scope && socket.assigns.current_scope.user
    user_id = user && user.id

    if connected?(socket) && user_id do
      Phoenix.PubSub.subscribe(Agora.PubSub, "feed:#{user_id}")
      Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{user_id}:notifications")
    end

    posts = Posts.list_feed_for(user_id)
    post_ids = Enum.map(posts, & &1.id)

    {:ok,
     socket
     |> assign(:empty_feed?, posts == [])
     |> assign(:live_now, [])
     |> assign(:reactions, Posts.reaction_summary_for(post_ids, user_id))
     |> assign(:comment_counts, Posts.comment_counts_for(post_ids))
     |> assign(:comment_modal, nil)
     |> stream(:posts, posts)}
  end

  @impl true
  def handle_event("toggle_reaction", %{"kind" => kind, "post_id" => post_id}, socket) do
    case socket.assigns.current_scope && socket.assigns.current_scope.user do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      user ->
        :ok = Posts.toggle_reaction(user.id, post_id, String.to_existing_atom(kind))
        summary = Posts.reaction_summary_for([post_id], user.id)

        {:noreply,
         socket
         |> assign(:reactions, Map.merge(socket.assigns.reactions, summary))
         |> stream_insert(:posts, Posts.get_post!(post_id))}
    end
  end

  def handle_event("open_comments", %{"post_id" => post_id}, socket) do
    {:noreply,
     assign(socket, :comment_modal, %{post_id: post_id, comments: Posts.list_comments(post_id)})}
  end

  def handle_event("close_comments", _params, socket) do
    {:noreply, assign(socket, :comment_modal, nil)}
  end

  def handle_event("add_comment", %{"post_id" => post_id, "body" => body}, socket) do
    case socket.assigns.current_scope && socket.assigns.current_scope.user do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      user ->
        case Posts.add_comment(user.id, post_id, body) do
          {:ok, _comment} ->
            {:noreply,
             socket
             |> assign(:comment_modal, %{post_id: post_id, comments: Posts.list_comments(post_id)})
             |> update(:comment_counts, &Map.update(&1, post_id, 1, fn n -> n + 1 end))
             |> push_event("reset-comment-form", %{})}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Couldn't post that comment.")}
        end
    end
  end

  @impl true
  def handle_info({:new_post, post_id}, socket) do
    user_id =
      socket.assigns.current_scope && socket.assigns.current_scope.user &&
        socket.assigns.current_scope.user.id

    summary = Posts.reaction_summary_for([post_id], user_id)

    {:noreply,
     socket
     |> assign(:empty_feed?, false)
     |> assign(:reactions, Map.merge(socket.assigns.reactions, summary))
     |> update(:comment_counts, &Map.put(&1, post_id, 0))
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
      <!-- Header -->
      <div class="flex items-center justify-between px-2 pt-2 pb-5">
        <div class="flex items-center gap-3">
          <div class="flex items-center justify-center size-9 rounded-xl bg-primary/10 text-primary">
            <.icon name="hero-rectangle-stack" class="size-5" />
          </div>
          <div>
            <h1 class="font-display text-xl font-bold text-base-content tracking-wide">
              Feed & Tidings
            </h1>
            <p class="text-xs text-base-content/50">Live updates from your community</p>
          </div>
        </div>

        <.link
          navigate={
            if @current_scope, do: ~p"/profile/#{@current_scope.user.id}", else: ~p"/users/log-in"
          }
          class="btn btn-ghost btn-xs text-xs font-semibold text-primary hover:bg-primary/10 rounded-lg"
        >
          <.icon name="hero-plus-circle" class="size-4" /> Share Tiding
        </.link>
      </div>

      <!-- Live Broadcast Alert Banners -->
      <div :if={@live_now != []} class="px-2 pb-5 space-y-3">
        <.link
          :for={banner <- @live_now}
          navigate={~p"/gatherings/#{banner.id}"}
          class="flex items-center gap-3.5 rounded-2xl bg-gradient-to-r from-primary to-rose-700 px-4 py-3.5 text-white
                 transition-all duration-200 hover:opacity-95 active:scale-95 shadow border border-white/10"
        >
          <div class="relative flex items-center justify-center size-8 rounded-full bg-white/20 shrink-0">
            <.icon name="hero-signal" class="size-4 text-white motion-safe:animate-pulse" />
          </div>
          <div class="flex-1 min-w-0">
            <span class="inline-flex items-center gap-1.5 text-[10px] font-extrabold tracking-wider uppercase bg-black/30 px-2 py-0.5 rounded-full text-white/90 mb-0.5">
              <span class="size-1.5 rounded-full bg-white motion-safe:animate-ping"></span>
              Live Broadcast
            </span>
            <p class="text-sm font-bold truncate">
              {banner.broadcaster_name} is live now — {banner.title}
            </p>
          </div>
          <span class="btn btn-sm bg-white text-primary border-none font-bold text-xs hover:bg-white/90 shrink-0 shadow">
            Join Room
          </span>
        </.link>
      </div>

      <!-- Feed Cards Stream -->
      <div id="feed" phx-update="stream" class="flex flex-col gap-3 px-2">
        <div :for={{dom_id, post} <- @streams.posts} id={dom_id}>
          <.feed_card
            post={post}
            navigate={~p"/posts/#{post.id}"}
            reactions={
              @reactions[post.id] ||
                %{heart_count: 0, torch_count: 0, hearted?: false, torched?: false}
            }
            comment_count={@comment_counts[post.id] || 0}
          />
        </div>
      </div>

      <.comment_modal
        post_id={@comment_modal && @comment_modal.post_id}
        comments={(@comment_modal && @comment_modal.comments) || []}
        current_scope={@current_scope}
      />

      <!-- Empty Feed State -->
      <div :if={@empty_feed?} class="flex flex-col items-center gap-4 px-4 py-16 text-center">
        <div class="relative flex items-center justify-center size-16 rounded-2xl bg-base-content/[0.04] text-primary border border-base-content/[0.06]">
          <.icon name="hero-user-group" class="size-8" />
        </div>
        <div class="space-y-1">
          <h3 class="font-display text-base font-bold text-base-content">
            Your feed is quiet — for now.
          </h3>
          <p class="text-xs text-base-content/50 max-w-xs leading-relaxed">
            Cling to people to see their Tidings, photos, and Gatherings here as they happen.
          </p>
        </div>
        <.link
          navigate={
            if @current_scope, do: ~p"/profile/#{@current_scope.user.id}", else: ~p"/users/log-in"
          }
          class="btn btn-primary btn-sm font-bold text-xs active:scale-95 transition-all mt-2 rounded-full px-5"
        >
          <.icon name="hero-pencil-square" class="size-4" /> Share a Tiding while you wait
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
