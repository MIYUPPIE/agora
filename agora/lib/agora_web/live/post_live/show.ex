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

  @impl true
  def handle_info({:reaction_updated, _post_id}, socket) do
    {:noreply, assign_reactions(socket, socket.assigns.post.id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen mesh-bg">
      <div class="flex items-center justify-between glass border-b border-white/5 px-4 py-2 sticky top-0 z-20">
        <.link navigate={~p"/"} class="flex items-center gap-2">
          <img src={~p"/images/agora-mark.png"} width="24" alt="Agora" />
          <span class="text-sm font-bold tracking-wide text-primary">AGORA</span>
        </.link>
        <.link :if={@viewer_profile} navigate={~p"/profile/#{@current_scope.user.id}"}>
          <.avatar
            avatar_url={@viewer_profile.avatar_url}
            display_name={@viewer_profile.display_name}
            size="size-8"
          />
        </.link>
      </div>

      <div class="flex items-center gap-3 px-4 py-4 rise-in">
        <.link navigate={~p"/profile/#{@post.user_id}"}>
          <.avatar
            avatar_url={@post.user.profile.avatar_url}
            display_name={@post.user.profile.display_name}
            size="size-10"
          />
        </.link>
        <h1 class="text-base font-medium text-base-content">
          {headline(@post)}
        </h1>
      </div>

      <div :if={@post.kind == :image_set} class="flex flex-col gap-2 px-4">
        <img
          :for={m <- @post.media}
          src={m.url}
          class="w-full object-cover rounded-box depth-card rise-in"
        />
      </div>

      <div :if={@post.kind == :audio} class="px-4 pb-2">
        <div class="rounded-box glass depth-card p-4 rise-in">
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
          <audio :if={!@post.waveform} controls src={audio_url(@post)} class="w-full" />
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
                ctx.fillStyle = "#a00000";
                const barWidth = width / Math.max(peaks.length, 1);
                const max = Math.max(...peaks, 1);
                peaks.forEach((p, i) => {
                  const h = Math.max((p / max) * height, 2);
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

      <div :if={@post.kind == :tiding} class="px-4 pb-2">
        <div class="rounded-box glass depth-card p-6 rise-in">
          <p class="text-lg text-base-content whitespace-pre-line">{@post.body}</p>
        </div>
      </div>

      <div class="flex items-center gap-3 px-4 py-4">
        <button
          type="button"
          phx-click="toggle_reaction"
          phx-value-kind="heart"
          class="flex items-center gap-1.5 rounded-full glass depth-card px-4 py-2
                 transition-all duration-200 hover:-translate-y-0.5 active:scale-95"
        >
          <.icon
            name="hero-heart"
            class={["size-5", @hearted? && "text-primary", !@hearted? && "text-base-content/60"]}
          />
          <span class="text-sm text-base-content/70">{@heart_count}</span>
        </button>
        <button
          type="button"
          phx-click="toggle_reaction"
          phx-value-kind="torch"
          class="flex items-center gap-1.5 rounded-full glass depth-card px-4 py-2
                 transition-all duration-200 hover:-translate-y-0.5 active:scale-95"
        >
          <.icon
            name="hero-fire"
            class={["size-5", @torched? && "text-primary", !@torched? && "text-base-content/60"]}
          />
          <span class="text-sm text-base-content/70">{@torch_count}</span>
        </button>
      </div>
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
