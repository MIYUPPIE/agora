defmodule AgoraWeb.ProfileLive do
  @moduledoc """
  The profile hub — avatar, name, tagline, stats, action row, and the
  owner's post feed. Bespoke full-bleed chrome, not the generic
  `Layouts.app` navbar — the red header band IS the page's top chrome,
  per the mockup.
  """

  use AgoraWeb, :live_view

  alias Agora.{Accounts, Gatherings, Posts, Profiles, Social}
  alias Agora.Posts.{ImageProcessor, Storage}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    owner = Accounts.get_user!(id)
    profile = Profiles.get_or_create!(owner)
    viewer = socket.assigns.current_scope && socket.assigns.current_scope.user
    is_owner = !!(viewer && viewer.id == owner.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{owner.id}:stats")

      if is_owner do
        Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{owner.id}:notifications")
      end
    end

    {:ok,
     socket
     |> assign(:owner, owner)
     |> assign(:profile, profile)
     |> assign(:is_owner, is_owner)
     |> assign(:composer, nil)
     |> assign(:live_now, [])
     |> assign_stats(owner.id, viewer)
     |> assign_posts()
     |> allow_upload(:images,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 5,
       max_file_size: 25_000_000
     )}
  end

  defp assign_stats(socket, owner_id, viewer) do
    socket
    |> assign(:clinger_count, Social.clinger_count(owner_id))
    |> assign(:cling_count, Social.cling_count(owner_id))
    |> assign(:post_count, Posts.count_for_user(owner_id))
    |> assign(:gathering_count, Gatherings.count_for_user(owner_id))
    |> assign(
      :clinging?,
      !!(viewer && viewer.id != owner_id && Social.clinging?(viewer.id, owner_id))
    )
  end

  defp assign_posts(socket) do
    assign(socket, :posts, Posts.list_for_user(socket.assigns.owner.id))
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

  def handle_event("open_composer", %{"kind" => kind}, socket) do
    {:noreply, assign(socket, :composer, String.to_existing_atom(kind))}
  end

  def handle_event("close_composer", _params, socket) do
    {:noreply, assign(socket, :composer, nil)}
  end

  def handle_event("validate_images", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :images, ref)}
  end

  def handle_event("post_tiding", %{"tiding" => %{"body" => body}}, socket) do
    with true <- socket.assigns.is_owner,
         {:ok, _post} <- Posts.create_tiding(socket.assigns.owner.id, %{"body" => body}) do
      {:noreply,
       socket
       |> assign(:composer, nil)
       |> assign_posts()
       |> assign(:post_count, Posts.count_for_user(socket.assigns.owner.id))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Couldn't post that tiding.")}
    end
  end

  def handle_event("post_images", %{"title" => title}, socket) do
    if socket.assigns.is_owner do
      uploaded =
        consume_uploaded_entries(socket, :images, fn %{path: path}, _entry ->
          with {:ok, processed_path, byte_size} <- ImageProcessor.process(path),
               {:ok, url} <- Storage.put(processed_path, image_key(), "image/jpeg") do
            File.rm(processed_path)
            {:ok, %{url: url, byte_size: byte_size}}
          end
        end)

      case uploaded do
        [] ->
          {:noreply, put_flash(socket, :error, "Choose at least one image.")}

        images ->
          case Posts.create_image_post(socket.assigns.owner.id, %{"title" => title}, images) do
            {:ok, _post} ->
              {:noreply,
               socket
               |> assign(:composer, nil)
               |> assign_posts()
               |> assign(:post_count, Posts.count_for_user(socket.assigns.owner.id))}

            {:error, _reason} ->
              {:noreply, put_flash(socket, :error, "Couldn't post those images.")}
          end
      end
    else
      {:noreply, socket}
    end
  end

  defp image_key, do: "posts/images/#{Ecto.UUID.generate()}.jpg"

  @impl true
  def handle_info({:stats_updated, _user_id}, socket) do
    {:noreply, assign_stats(socket, socket.assigns.owner.id, current_viewer(socket))}
  end

  def handle_info({:gathering_live_notification, gathering_id, broadcaster_name, title}, socket) do
    banner = %{id: gathering_id, broadcaster_name: broadcaster_name, title: title}
    {:noreply, assign(socket, :live_now, [banner | socket.assigns.live_now])}
  end

  defp current_viewer(socket),
    do: socket.assigns.current_scope && socket.assigns.current_scope.user

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["min-h-screen bg-base-100", @is_owner && "pb-24"]}>
      <div class="relative px-4 pt-6 pb-4 overflow-hidden">
        <div class="absolute inset-0 bg-gradient-to-br from-primary via-primary to-secondary"></div>
        <div class="absolute inset-0 bg-gradient-to-t from-black/25 via-transparent to-white/5"></div>
        <div class="relative flex items-start gap-3">
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
                <li><.link navigate={~p"/feed"}>Feed</.link></li>
                <li><.link href={~p"/users/settings"}>Settings</.link></li>
                <li><.link href={~p"/users/log-out"} method="delete">Log out</.link></li>
              </ul>
            </details>
          </div>
        </div>

        <div class="relative grid grid-cols-4 gap-2 mt-5">
          <.stat count={@post_count} label="Posts" />
          <.stat count={@gathering_count} label="Gatherings" />
          <.stat count={@clinger_count} label="Clingers" />
          <.stat count={@cling_count} label="Clings" />
        </div>
      </div>

      <div :if={@live_now != []} class="px-4 pt-4 pb-2 space-y-2">
        <.link
          :for={banner <- @live_now}
          navigate={~p"/gatherings/#{banner.id}"}
          class="flex items-center gap-2 rounded-lg bg-primary depth-glow px-4 py-3 text-white
                 transition-all duration-200 hover:bg-primary/90 hover:-translate-y-0.5"
        >
          <.icon name="hero-signal" class="size-5 shrink-0 motion-safe:animate-pulse" />
          <span class="text-sm font-medium">
            {banner.broadcaster_name} is live now — {banner.title}
          </span>
        </.link>
      </div>

      <div :if={@is_owner || @posts != []} class="flex gap-3 px-4 pb-4 overflow-x-auto">
        <.new_post_circle :if={@is_owner} phx-click="open_composer" phx-value-kind="tiding" />
        <.post_circle
          :for={post <- Enum.take(@posts, 8)}
          post={post}
          navigate={~p"/posts/#{post.id}"}
        />
      </div>

      <div :if={@composer == :tiding} class="mx-4 mb-4 rounded-box glass depth-card p-4 rise-in">
        <form phx-submit="post_tiding">
          <textarea
            name="tiding[body]"
            class="textarea w-full bg-base-100/60"
            placeholder="Share a tiding…"
            rows="3"
            required
          ></textarea>
          <div class="flex justify-end gap-2 mt-2">
            <button type="button" phx-click="close_composer" class="btn btn-sm btn-ghost">Cancel</button>
            <button type="submit" class="btn btn-sm btn-primary active:scale-95 transition-transform">
              Post
            </button>
          </div>
        </form>
      </div>

      <div :if={@composer == :image} class="mx-4 mb-4 rounded-box glass depth-card p-4 rise-in">
        <form phx-submit="post_images" phx-change="validate_images" id="image-upload-form">
          <.live_file_input upload={@uploads.images} />

          <div :for={entry <- @uploads.images.entries} class="flex items-center gap-2 mt-2">
            <.live_img_preview entry={entry} class="h-14 w-14 object-cover rounded" />
            <progress value={entry.progress} max="100" class="progress progress-primary flex-1">
              {entry.progress}%
            </progress>
            <button
              type="button"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
              class="btn btn-xs btn-ghost"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <input
            type="text"
            name="title"
            placeholder="Caption (optional)"
            class="input w-full bg-base-100/60 mt-2"
          />

          <div class="flex justify-end gap-2 mt-2">
            <button type="button" phx-click="close_composer" class="btn btn-sm btn-ghost">Cancel</button>
            <button type="submit" class="btn btn-sm btn-primary active:scale-95 transition-transform">
              Post
            </button>
          </div>
        </form>
      </div>

      <div :if={@posts != []} class="flex flex-col gap-2 px-4 pb-4">
        <.post_row :for={post <- @posts} post={post} navigate={~p"/posts/#{post.id}"} />
      </div>

      <p :if={@posts == []} class="px-4 py-12 text-center text-base-content/50">
        No posts yet.
      </p>
    </div>

    <div
      :if={@is_owner}
      class="fixed bottom-0 inset-x-0 z-30 glass depth-card border-t border-white/10 px-4 pt-3"
      style="padding-bottom: calc(0.75rem + env(safe-area-inset-bottom))"
    >
      <div class="grid grid-cols-4 gap-2 max-w-2xl mx-auto">
        <.action_pill
          icon="hero-microphone"
          label="Start Gathering"
          phx-click={JS.navigate(~p"/gatherings/new")}
        />
        <.action_pill
          icon="hero-photo"
          label="Upload Image"
          phx-click="open_composer"
          phx-value-kind="image"
        />
        <.action_pill
          icon="hero-megaphone"
          label="Tidings"
          phx-click="open_composer"
          phx-value-kind="tiding"
        />
        <.action_pill
          icon="hero-signal"
          label="Join Gathering"
          phx-click={JS.navigate(~p"/gatherings")}
        />
      </div>
    </div>

    <Layouts.flash_group flash={@flash} />
    """
  end
end
