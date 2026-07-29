defmodule AgoraWeb.PostLive.Show do
  @moduledoc """
  The post detail view — full media (image gallery, audio player +
  waveform, or tiding text) and live Heart/Torch reactions. Bespoke
  chrome again: a slim dark top bar, not the generic navbar.
  """

  use AgoraWeb, :live_view

  alias Agora.{Posts, Profiles}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    post = Posts.get_post!(id)
    viewer = current_viewer(socket)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Agora.PubSub, "post:#{post.id}")
    end

    {:ok,
     socket
     |> assign(:post, post)
     |> assign(:viewer_profile, viewer && Profiles.get_or_create!(viewer))
     |> assign(:comments, Posts.list_comments(post.id))
     |> assign_reactions(post.id)}
  end

  defp assign_reactions(socket, post_id) do
    viewer = current_viewer(socket)
    counts = Posts.reaction_counts(post_id)

    socket
    |> assign(:heart_count, counts.heart)
    |> assign(:torch_count, counts.torch)
    |> assign(:hearted?, !!(viewer && Posts.reacted?(viewer.id, post_id, :heart)))
    |> assign(:torched?, !!(viewer && Posts.reacted?(viewer.id, post_id, :torch)))
  end

  defp current_viewer(socket),
    do: socket.assigns.current_scope && socket.assigns.current_scope.user

  @impl true
  def handle_event("toggle_reaction", %{"kind" => kind}, socket) do
    case current_viewer(socket) do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      viewer ->
        :ok =
          Posts.toggle_reaction(viewer.id, socket.assigns.post.id, String.to_existing_atom(kind))

        {:noreply, assign_reactions(socket, socket.assigns.post.id)}
    end
  end

  def handle_event("open_comments", %{"post_id" => post_id}, socket) do
    {:noreply, assign(socket, :comments, Posts.list_comments(post_id))}
  end

  def handle_event("close_comments", _params, socket), do: {:noreply, socket}

  def handle_event("add_comment", %{"post_id" => post_id, "body" => body}, socket) do
    case current_viewer(socket) do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}

      viewer ->
        case Posts.add_comment(viewer.id, post_id, body) do
          {:ok, _comment} ->
            {:noreply,
             socket
             |> assign(:comments, Posts.list_comments(post_id))
             |> push_event("reset-comment-form", %{})}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Couldn't post that comment.")}
        end
    end
  end

  @impl true
  def handle_info({:reaction_updated, _post_id}, socket) do
    {:noreply, assign_reactions(socket, socket.assigns.post.id)}
  end

  def handle_info({:comment_added, post_id}, socket) do
    {:noreply, assign(socket, :comments, Posts.list_comments(post_id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen mesh-bg font-sans text-base-content pb-12">
      <!-- Top Navigation Header -->
      <div class="glass border-b border-base-content/10 px-4 sm:px-6 py-3 sticky top-0 z-30 flex items-center justify-between">
        <div class="flex items-center gap-3">
          <.link
            navigate={~p"/feed"}
            class="btn btn-circle btn-xs btn-ghost text-base-content/70 hover:text-base-content"
          >
            <.icon name="hero-arrow-left" class="size-4" />
          </.link>
          <.link navigate={~p"/"} class="shrink-0">
            <.logo size="size-6 sm:size-7" text_size="text-xs sm:text-sm" />
          </.link>
        </div>

        <div class="flex items-center gap-2">
          <button
            type="button"
            data-theme-toggle
            class="btn btn-ghost btn-xs btn-circle text-base-content/60 hover:text-base-content"
            title="Toggle day/night theme"
            aria-label="Toggle day/night theme"
          >
            <.icon name="hero-sun" class="theme-icon-sun size-4" />
            <.icon name="hero-moon" class="theme-icon-moon size-4" />
          </button>

          <.link :if={@viewer_profile} navigate={~p"/profile/#{@current_scope.user.id}"}>
            <.avatar
              avatar_url={@viewer_profile.avatar_url}
              display_name={@viewer_profile.display_name}
              size="size-8"
            />
          </.link>
        </div>
      </div>

      <div class="max-w-xl mx-auto px-4 sm:px-6 pt-6 space-y-5">
        <!-- Author Info Header -->
        <div class="flex items-center gap-3.5 rise-in">
          <.link navigate={~p"/profile/#{@post.user_id}"}>
            <.avatar
              avatar_url={@post.user.profile.avatar_url}
              display_name={@post.user.profile.display_name}
              size="size-12"
            />
          </.link>
          <div class="flex-1 min-w-0">
            <.link
              navigate={~p"/profile/#{@post.user_id}"}
              class="font-display text-base font-bold text-base-content hover:text-primary transition-colors block truncate"
            >
              {@post.user.profile.display_name}
            </.link>
            <p class="text-xs text-base-content/50">
              {headline(@post)}
            </p>
          </div>
        </div>

        <!-- Post Content Card -->
        <!-- Image Set -->
        <div :if={@post.kind == :image_set} class="flex flex-col gap-3">
          <img
            :for={m <- @post.media}
            src={m.url}
            class="w-full object-cover rounded-2xl depth-card rise-in border border-base-content/10"
          />
        </div>

        <!-- Audio Post -->
        <div :if={@post.kind == :audio} class="rise-in">
          <div class="rounded-2xl glass depth-card p-5 border border-base-content/10 space-y-3">
            <div class="flex items-center justify-between text-xs font-bold text-base-content/80">
              <span class="flex items-center gap-2">
                <.icon name="hero-musical-note" class="size-4 text-primary" /> Audio Waveform Preview
              </span>
              <span class="text-[10px] text-base-content/50 uppercase font-mono">Tap waveform to play</span>
            </div>
            <div class="rounded-xl well p-4 border border-base-content/5 flex items-center justify-center">
              <canvas
                :if={@post.waveform}
                id={"waveform-#{@post.id}"}
                phx-hook=".WaveformPlayer"
                phx-update="ignore"
                data-peaks={Jason.encode!(@post.waveform)}
                data-src={audio_url(@post)}
                width="600"
                height="80"
                class="w-full h-20 cursor-pointer"
              />
              <audio
                :if={!@post.waveform}
                controls
                src={audio_url(@post)}
                class="w-full accent-primary"
              />
            </div>
          </div>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".WaveformPlayer">
            export default {
              mounted() {
                const ctx = this.el.getContext("2d");
                const peaks = JSON.parse(this.el.dataset.peaks || "[]");
                const audio = new Audio(this.el.dataset.src);
                this.audio = audio;

                const draw = () => {
                  const { width, height } = this.el;
                  ctx.clearRect(0, 0, width, height);
                  ctx.fillStyle = "#e11d48";
                  const barWidth = width / Math.max(peaks.length, 1);
                  const max = Math.max(...peaks, 1);
                  peaks.forEach((p, i) => {
                    const h = Math.max((p / max) * height, 3);
                    ctx.fillRect(i * barWidth, (height - h) / 2, Math.max(barWidth - 1, 1), h);
                  });
                };
                draw();

                this.el.addEventListener("click", () => {
                  if (audio.paused) audio.play(); else audio.pause();
                });
              },
              destroyed() {
                this.audio?.pause();
              }
            };
          </script>
        </div>

        <!-- Tiding Text -->
        <div :if={@post.kind == :tiding} class="rise-in">
          <div class="rounded-2xl glass depth-card p-6 border border-base-content/10">
            <p class="text-base sm:text-lg leading-relaxed text-base-content/95 font-normal whitespace-pre-line">
              {@post.body}
            </p>
          </div>
        </div>

        <!-- Reactions Bar -->
        <div class="flex items-center gap-3 pt-2 rise-in">
          <button
            type="button"
            phx-click="toggle_reaction"
            phx-value-kind="heart"
            class={[
              "flex items-center gap-2 rounded-full px-4 py-2 text-xs font-bold tracking-wide border",
              "transition-all duration-200 active:scale-95 shadow-md",
              @hearted? && "bg-primary/20 text-primary border-primary/40 depth-glow",
              !@hearted? &&
                "glass text-base-content/70 border-base-content/10 hover:text-base-content"
            ]}
          >
            <.icon
              name="hero-heart"
              class={[
                "size-4",
                @hearted? && "fill-current text-primary",
                !@hearted? && "text-base-content/60"
              ]}
            />
            <span>{@heart_count}</span>
          </button>

          <button
            type="button"
            phx-click="toggle_reaction"
            phx-value-kind="torch"
            class={[
              "flex items-center gap-2 rounded-full px-4 py-2 text-xs font-bold tracking-wide border",
              "transition-all duration-200 active:scale-95 shadow-md",
              @torched? && "bg-rose-500/20 text-rose-400 border-rose-500/40 depth-glow",
              !@torched? &&
                "glass text-base-content/70 border-base-content/10 hover:text-base-content"
            ]}
          >
            <.icon
              name="hero-fire"
              class={[
                "size-4",
                @torched? && "fill-current text-rose-400",
                !@torched? && "text-base-content/60"
              ]}
            />
            <span>{@torch_count}</span>
          </button>

          <.comment_button post_id={@post.id} count={length(@comments)} />
        </div>
      </div>

      <.comment_modal post_id={@post.id} comments={@comments} current_scope={@current_scope} />
    </div>
    """
  end

  defp headline(%{kind: :tiding, body: body}), do: body
  defp headline(%{title: title}) when is_binary(title) and title != "", do: title
  defp headline(%{kind: :audio}), do: "Untitled recording"
  defp headline(%{kind: :image_set}), do: "Untitled post"

  defp audio_url(%{media: media}) do
    Enum.find_value(media, fn m -> m.kind == :audio && m.url end)
  end
end
