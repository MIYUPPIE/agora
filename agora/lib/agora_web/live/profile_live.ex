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
     )
     |> allow_upload(:avatar,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 1,
       max_file_size: 10_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )
     |> allow_upload(:cover,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 1,
       max_file_size: 15_000_000,
       auto_upload: true,
       progress: &handle_progress/3
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
  def handle_event("validate_avatar", _params, socket), do: {:noreply, socket}
  def handle_event("validate_cover", _params, socket), do: {:noreply, socket}

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
  defp avatar_key, do: "profiles/avatars/#{Ecto.UUID.generate()}.jpg"
  defp cover_key, do: "profiles/covers/#{Ecto.UUID.generate()}.jpg"

  def handle_progress(:avatar, entry, socket) do
    if entry.done? and socket.assigns.is_owner do
      {:noreply, put_profile_image(socket, :avatar, entry, :avatar_url, avatar_key())}
    else
      {:noreply, socket}
    end
  end

  def handle_progress(:cover, entry, socket) do
    if entry.done? and socket.assigns.is_owner do
      {:noreply, put_profile_image(socket, :cover, entry, :cover_url, cover_key())}
    else
      {:noreply, socket}
    end
  end

  def handle_progress(_upload, _entry, socket), do: {:noreply, socket}

  defp put_profile_image(socket, upload_name, entry, field, key) do
    url =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        with {:ok, processed_path, _byte_size} <- ImageProcessor.process(path),
             {:ok, url} <- Storage.put(processed_path, key, "image/jpeg") do
          File.rm(processed_path)
          {:ok, url}
        end
      end)

    case Profiles.update_profile(socket.assigns.profile, %{Atom.to_string(field) => url}) do
      {:ok, profile} ->
        assign(socket, :profile, profile)

      {:error, _changeset} ->
        put_flash(socket, :error, "Couldn't save that #{upload_name} image.")
    end
  end

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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="relative py-4 font-sans">
        <!-- Profile Hero Header -->
        <div class="relative max-w-2xl mx-auto px-4 sm:px-6">
          <div class="rounded-3xl bg-base-200/60 border border-base-content/[0.06] overflow-hidden">
            <!-- Cover Picture -->
            <div class="relative h-28 sm:h-44 w-full bg-gradient-to-br from-primary/25 to-rose-700/25 group/cover">
              <img
                :if={@profile.cover_url}
                src={@profile.cover_url}
                class="absolute inset-0 w-full h-full object-cover"
              />
              <form
                :if={@is_owner}
                id="cover-form"
                phx-change="validate_cover"
                class="absolute inset-0"
              >
                <label class="absolute inset-0 flex items-center justify-center gap-1.5 cursor-pointer bg-black/0 group-hover/cover:bg-black/40 transition-colors duration-200">
                  <span class="flex items-center gap-1.5 text-xs font-bold text-white opacity-0 group-hover/cover:opacity-100 transition-opacity duration-200">
                    <.icon name="hero-camera" class="size-4" /> Change cover
                  </span>
                  <.live_file_input upload={@uploads.cover} class="hidden" />
                </label>
              </form>
            </div>

            <div class="relative -mt-10 sm:-mt-12 px-6 sm:px-8 pb-6 sm:pb-8 flex flex-col sm:flex-row items-center sm:items-end gap-5 text-center sm:text-left">
              <!-- Avatar Ring -->
              <div class="relative shrink-0 group/avatar">
                <div class="rounded-full ring-4 ring-base-200 shadow-lg">
                  <.avatar
                    avatar_url={@profile.avatar_url}
                    display_name={@profile.display_name}
                    size="size-20 sm:size-24"
                  />
                </div>
                <form
                  :if={@is_owner}
                  id="avatar-form"
                  phx-change="validate_avatar"
                  class="absolute inset-0"
                >
                  <label class="absolute inset-0 rounded-full flex items-center justify-center cursor-pointer bg-black/0 group-hover/avatar:bg-black/50 transition-colors duration-200">
                    <.icon
                      name="hero-camera"
                      class="size-5 text-white opacity-0 group-hover/avatar:opacity-100 transition-opacity duration-200"
                    />
                    <.live_file_input upload={@uploads.avatar} class="hidden" />
                  </label>
                </form>
              </div>

              <!-- Profile Info & Bio -->
              <div class="flex-1 min-w-0 space-y-2 pt-2 sm:pt-0">
                <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                  <div>
                    <h1 class="font-display text-2xl font-bold text-base-content tracking-wide">
                      {@profile.display_name}
                    </h1>
                    <p class="text-xs text-base-content/50 font-medium">{@owner.email}</p>
                  </div>

                  <!-- Cling Action Button -->
                  <div :if={!@is_owner} class="shrink-0">
                    <button
                      :if={!@clinging?}
                      phx-click="cling"
                      class="btn btn-primary btn-sm rounded-full font-semibold px-6 active:scale-95 transition-all shadow"
                    >
                      Cling
                    </button>
                    <button
                      :if={@clinging?}
                      phx-click="uncling"
                      class="btn btn-outline btn-sm rounded-full font-semibold border-base-content/20 hover:bg-base-content/10 text-base-content px-6 active:scale-95 transition-all"
                    >
                      Clinging
                    </button>
                  </div>
                </div>

                <p
                  :if={@profile.bio not in [nil, ""]}
                  class="text-xs sm:text-sm text-base-content/80 leading-relaxed font-normal"
                >
                  {@profile.bio}
                </p>
              </div>
            </div>
          </div>

          <!-- Stats Grid Bar -->
          <div class="grid grid-cols-4 gap-2.5 mt-4">
            <.stat count={@post_count} label="Posts" />
            <.stat count={@gathering_count} label="Gatherings" />
            <.stat count={@clinger_count} label="Clingers" />
            <.stat count={@cling_count} label="Clings" />
          </div>

          <!-- Quick Action Bar for Profile Owner (Inline) -->
          <div
            :if={@is_owner}
            class="grid grid-cols-4 gap-2 mt-4 p-3 rounded-2xl bg-base-200/60 border border-base-content/[0.06]"
          >
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

        <!-- Main Profile Content Body -->
        <div class="max-w-2xl mx-auto py-6 space-y-4 px-4 sm:px-6">
          <!-- Live Now Banner -->
          <div :if={@live_now != []} class="space-y-2">
            <.link
              :for={banner <- @live_now}
              navigate={~p"/gatherings/#{banner.id}"}
              class="flex items-center gap-3 rounded-2xl bg-gradient-to-r from-primary to-rose-600 p-4 text-white
                     transition-all duration-200 hover:opacity-95 active:scale-95 shadow border border-white/10"
            >
              <.icon name="hero-signal" class="size-5 shrink-0 motion-safe:animate-pulse" />
              <span class="text-xs sm:text-sm font-bold truncate">
                {banner.broadcaster_name} is live now — {banner.title}
              </span>
            </.link>
          </div>

          <!-- Recent Activity Circle Strip -->
          <div
            :if={@is_owner || @posts != []}
            class="flex items-center gap-3 pb-2 overflow-x-auto custom-scrollbar"
          >
            <.new_post_circle :if={@is_owner} phx-click="open_composer" phx-value-kind="tiding" />
            <.post_circle
              :for={post <- Enum.take(@posts, 8)}
              post={post}
              navigate={~p"/posts/#{post.id}"}
            />
          </div>

          <!-- Tiding Composer Modal Card -->
          <div
            :if={@composer == :tiding}
            class="rounded-2xl bg-base-200/80 border border-base-content/[0.08] p-5"
          >
            <h3 class="font-display text-sm font-bold text-base-content mb-2 flex items-center gap-2">
              <.icon name="hero-megaphone" class="size-4 text-primary" /> Publish Tiding
            </h3>
            <form phx-submit="post_tiding">
              <textarea
                name="tiding[body]"
                class="textarea w-full well border-base-content/10 text-base-content placeholder:text-base-content/30 focus:border-primary focus:ring-1 focus:ring-primary rounded-xl text-sm leading-relaxed"
                placeholder="What voice or thought do you want to share with your clings today?"
                rows="3"
                required
              ></textarea>
              <div class="flex justify-end gap-2 mt-3">
                <button
                  type="button"
                  phx-click="close_composer"
                  class="btn btn-sm btn-ghost text-xs text-base-content/60"
                >Cancel</button>
                <button
                  type="submit"
                  class="btn btn-sm btn-primary font-bold text-xs active:scale-95 transition-all px-5"
                >
                  Publish
                </button>
              </div>
            </form>
          </div>

          <!-- Image Set Composer Modal Card -->
          <div
            :if={@composer == :image}
            class="rounded-2xl bg-base-200/80 border border-base-content/[0.08] p-5"
          >
            <h3 class="font-display text-sm font-bold text-base-content mb-2 flex items-center gap-2">
              <.icon name="hero-photo" class="size-4 text-primary" /> Upload Photo Collection
            </h3>
            <form
              phx-submit="post_images"
              phx-change="validate_images"
              id="image-upload-form"
              class="space-y-3"
            >
              <div class="p-4 rounded-xl border border-dashed border-base-content/20 well text-center">
                <.live_file_input
                  upload={@uploads.images}
                  class="file-input file-input-primary file-input-sm w-full max-w-xs"
                />
              </div>

              <div
                :for={entry <- @uploads.images.entries}
                class="flex items-center gap-3 p-2 rounded-xl bg-base-content/[0.04] border border-base-content/[0.05]"
              >
                <.live_img_preview entry={entry} class="h-12 w-12 object-cover rounded-lg shrink-0" />
                <progress
                  value={entry.progress}
                  max="100"
                  class="progress progress-primary flex-1 h-2"
                >
                  {entry.progress}%
                </progress>
                <button
                  type="button"
                  phx-click="cancel_upload"
                  phx-value-ref={entry.ref}
                  class="btn btn-xs btn-ghost text-error"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>

              <input
                type="text"
                name="title"
                placeholder="Caption (optional)"
                class="input w-full well border-base-content/10 text-base-content placeholder:text-base-content/30 focus:border-primary focus:ring-1 focus:ring-primary rounded-xl text-xs h-10"
              />

              <div class="flex justify-end gap-2 pt-1">
                <button
                  type="button"
                  phx-click="close_composer"
                  class="btn btn-sm btn-ghost text-xs text-base-content/60"
                >Cancel</button>
                <button
                  type="submit"
                  class="btn btn-sm btn-primary font-bold text-xs active:scale-95 transition-all px-5"
                >
                  Publish Photos
                </button>
              </div>
            </form>
          </div>

          <!-- Posts List -->
          <div :if={@posts != []} class="flex flex-col gap-3">
            <.post_row :for={post <- @posts} post={post} navigate={~p"/posts/#{post.id}"} />
          </div>

          <!-- Empty Posts State -->
          <div :if={@posts == []} class="py-12 text-center text-base-content/40 space-y-1">
            <.icon name="hero-document-text" class="size-8 text-base-content/20 mx-auto" />
            <p class="text-sm font-medium">No posts yet.</p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
