defmodule AgoraWeb.AgoraComponents do
  @moduledoc """
  Agora-specific UI components — the domain look (stats, avatars, action
  pills) as opposed to `CoreComponents`' framework-generic building blocks.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: AgoraWeb.Endpoint,
    router: AgoraWeb.Router,
    statics: AgoraWeb.static_paths()

  alias Phoenix.LiveView.JS

  import AgoraWeb.CoreComponents, only: [icon: 1, modal: 1, show_modal: 2]

  attr :count, :integer, required: true
  attr :label, :string, required: true

  def stat(assigns) do
    ~H"""
    <div class="text-center rounded-2xl bg-base-content/[0.04] hover:bg-base-content/[0.07] py-3.5 px-3 border border-base-content/[0.06] transition-all duration-200 group">
      <div class="font-display text-2xl font-extrabold text-base-content tracking-tight group-hover:text-primary transition-colors">
        {@count}
      </div>
      <div class="text-[10px] font-bold text-base-content/50 tracking-wider uppercase mt-0.5">
        {@label}
      </div>
    </div>
    """
  end

  attr :avatar_url, :string, default: nil
  attr :display_name, :string, required: true
  attr :size, :string, default: "size-16"

  def avatar(assigns) do
    ~H"""
    <div class={[
      @size,
      "rounded-full overflow-hidden shrink-0 ring-1 ring-base-content/10 group-hover:ring-primary/50 transition-all duration-200"
    ]}>
      <img :if={@avatar_url} src={@avatar_url} alt={@display_name} class="w-full h-full object-cover" />
      <div
        :if={!@avatar_url}
        class="w-full h-full flex items-center justify-center bg-base-300 text-base-content/70 font-bold text-sm tracking-wider"
      >
        {initial(@display_name)}
      </div>
    </div>
    """
  end

  defp initial(name) when is_binary(name) do
    name |> String.trim() |> String.first() |> Kernel.||("?") |> String.upcase()
  end

  defp initial(_), do: "?"

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :rest, :global

  def action_pill(assigns) do
    ~H"""
    <button
      type="button"
      class="flex flex-col items-center gap-1.5 rounded-2xl bg-base-content/[0.04] hover:bg-base-content/[0.08] active:scale-95 px-3 py-2.5 text-base-content
             transition-all duration-200 border border-base-content/[0.05] group"
      {@rest}
    >
      <.icon name={@icon} class="size-5 text-primary group-hover:scale-110 transition-transform" />
      <span class="text-[11px] font-semibold leading-tight text-center tracking-wide text-base-content/90">{@label}</span>
    </button>
    """
  end

  @doc """
  A single compact feed/profile row: icon + title + muted meta.
  """
  attr :post, :any, required: true
  attr :navigate, :any, required: true

  def post_row(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="flex items-center gap-3 px-4 py-3.5 rounded-2xl bg-base-content/[0.03] hover:bg-base-content/[0.07] border border-base-content/[0.04]
             transition-all duration-200 active:scale-[0.99] group"
    >
      <div class="flex items-center justify-center size-9 rounded-xl bg-primary/10 text-primary group-hover:bg-primary group-hover:text-white transition-colors shrink-0">
        <.icon name={row_icon(@post.kind)} class="size-5" />
      </div>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-medium text-base-content/90 truncate group-hover:text-base-content transition-colors">
          {row_title(@post)}
        </p>
        <p :if={row_meta(@post)} class="text-xs text-base-content/50 truncate">
          {row_meta(@post)}
        </p>
      </div>
      <.icon
        name="hero-chevron-right"
        class="size-4 text-base-content/30 group-hover:text-base-content/70 group-hover:translate-x-0.5 transition-all"
      />
    </.link>
    """
  end

  defp row_icon(:audio), do: "hero-musical-note"
  defp row_icon(:image_set), do: "hero-photo"
  defp row_icon(:tiding), do: "hero-megaphone"

  defp row_title(%{kind: :tiding, body: body}), do: truncate(body, 60)
  defp row_title(%{title: title}) when is_binary(title) and title != "", do: title
  defp row_title(%{kind: :audio}), do: "Untitled recording"
  defp row_title(%{kind: :image_set}), do: "Untitled post"

  defp row_meta(%{kind: :audio, duration_ms: ms}) when is_integer(ms),
    do: "Listen: #{format_duration(ms)}"

  defp row_meta(%{kind: :image_set, media: media}) when is_list(media) do
    count = length(media)
    "#{count} #{if count == 1, do: "Image", else: "Images"}"
  end

  defp row_meta(_), do: nil

  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max) <> "…"

  @doc "Formats milliseconds as M:SS for audio post durations."
  def format_duration(ms) when is_integer(ms) do
    total_seconds = div(ms, 1000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end

  def format_duration(_), do: "0:00"

  @doc """
  A rich feed card: author + relative time, per-kind content preview,
  live heart/torch/comment toggles, and Instagram-style autoplay —
  multi-image posts auto-advance like a story carousel and audio posts
  auto-play/pause as they enter/leave the viewport (see the `.AutoplayCarousel`
  and `.AutoplayAudio` colocated hooks below).
  """
  attr :post, :any, required: true
  attr :navigate, :any, required: true
  attr :reactions, :map, required: true
  attr :comment_count, :integer, default: 0

  def feed_card(assigns) do
    ~H"""
    <div class="rounded-2xl bg-base-200/60 hover:bg-base-200/90 border border-base-content/[0.06] transition-all duration-200 overflow-hidden">
      <!-- Card Header -->
      <.link navigate={@navigate} class="flex items-center gap-3 p-4 pb-3 group">
        <.avatar
          avatar_url={@post.user.profile.avatar_url}
          display_name={@post.user.profile.display_name}
          size="size-10"
        />
        <div class="flex-1 min-w-0">
          <p class="text-sm font-bold text-base-content group-hover:text-primary transition-colors truncate">
            {@post.user.profile.display_name}
          </p>
          <p class="text-xs font-medium text-base-content/40">{time_ago(@post.inserted_at)}</p>
        </div>
        <span class="flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full bg-base-content/[0.05] text-base-content/70">
          <.icon name={row_icon(@post.kind)} class="size-3.5 text-primary" />
          {kind_label(@post.kind)}
        </span>
      </.link>

      <!-- Card Body Content -->
      <div class="px-4 pb-4">
        <!-- Tiding Text -->
        <.link
          :if={@post.kind == :tiding}
          navigate={@navigate}
          class="block text-sm leading-relaxed text-base-content/90 font-normal whitespace-pre-line line-clamp-5 bg-base-content/[0.02] p-3.5 rounded-xl border border-base-content/[0.04]"
        >
          {@post.body}
        </.link>

        <!-- Image Carousel — autoplays like an Instagram story when >1 photo -->
        <div :if={@post.kind == :image_set}>
          <div
            :if={length(@post.media) > 1}
            id={"carousel-#{@post.id}"}
            phx-hook=".AutoplayCarousel"
            phx-update="ignore"
            class="relative rounded-xl overflow-hidden border border-base-content/[0.06] bg-black/20 select-none"
          >
            <.link navigate={@navigate} class="relative block aspect-square sm:aspect-video w-full">
              <img
                :for={{m, idx} <- Enum.with_index(@post.media)}
                src={m.url}
                class={[
                  "carousel-slide absolute inset-0 w-full h-full object-cover transition-opacity duration-500",
                  if(idx == 0, do: "opacity-100 z-10", else: "opacity-0")
                ]}
              />
            </.link>
            <button
              type="button"
              class="carousel-prev absolute inset-y-0 left-0 w-1/3 z-20 cursor-w-resize"
              aria-label="Previous image"
            />
            <button
              type="button"
              class="carousel-next absolute inset-y-0 right-0 w-1/3 z-20 cursor-e-resize"
              aria-label="Next image"
            />
            <span class="carousel-counter absolute top-2.5 right-2.5 z-20 text-[10px] font-bold px-2 py-0.5 rounded-full bg-black/50 text-white backdrop-blur-sm pointer-events-none">
              1/{length(@post.media)}
            </span>
            <div class="absolute bottom-2.5 inset-x-0 z-20 flex items-center justify-center gap-1.5 pointer-events-none">
              <span
                :for={{_m, idx} <- Enum.with_index(@post.media)}
                class={[
                  "carousel-dot size-1.5 rounded-full transition-colors duration-300",
                  if(idx == 0, do: "bg-white", else: "bg-white/40")
                ]}
              />
            </div>
          </div>

          <.link
            :if={length(@post.media) == 1}
            navigate={@navigate}
            class="block rounded-xl overflow-hidden border border-base-content/[0.06]"
          >
            <img src={hd(@post.media).url} class="aspect-video sm:aspect-square w-full object-cover" />
          </.link>

          <.link
            :if={@post.title not in [nil, ""]}
            navigate={@navigate}
            class="block mt-2.5 text-sm font-medium text-base-content/80"
          >
            {@post.title}
          </.link>
        </div>

        <!-- Audio Recording Track Bar — auto-plays/pauses on scroll, like a Reel -->
        <div
          :if={@post.kind == :audio}
          id={"audio-card-#{@post.id}"}
          phx-hook=".AutoplayAudio"
          phx-update="ignore"
          data-src={audio_url(@post)}
          data-duration-ms={@post.duration_ms}
          class="flex items-center gap-3.5 rounded-xl well p-3.5 border border-base-content/[0.06]"
        >
          <button
            type="button"
            class="audio-toggle flex items-center justify-center size-10 rounded-full bg-primary text-white shrink-0 depth-glow hover:scale-105 transition-transform"
            aria-label="Play/pause"
          >
            <.icon name="hero-play" class="audio-icon-play size-5 ml-0.5" />
            <.icon name="hero-pause" class="audio-icon-pause size-5 hidden" />
          </button>
          <.link navigate={@navigate} class="flex-1 min-w-0">
            <p class="text-sm font-bold text-base-content truncate">
              {if @post.title not in [nil, ""], do: @post.title, else: "Untitled recording"}
            </p>
            <div class="flex items-center gap-2 mt-1.5">
              <div class="audio-progress relative h-1.5 rounded-full bg-base-content/10 overflow-hidden flex-1">
                <div
                  class="audio-fill absolute inset-y-0 left-0 bg-primary rounded-full"
                  style="width: 0%"
                />
              </div>
              <span class="audio-time text-xs font-mono text-base-content/50 shrink-0 tabular-nums">
                {format_duration(@post.duration_ms)}
              </span>
            </div>
          </.link>
        </div>
      </div>

      <!-- Reaction Buttons Bar -->
      <div class="flex items-center gap-3 px-4 py-2.5 bg-black/30 border-t border-base-content/[0.04]">
        <button
          type="button"
          phx-click="toggle_reaction"
          phx-value-kind="heart"
          phx-value-post_id={@post.id}
          class={[
            "flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold tracking-wide transition-all active:scale-95",
            @reactions.hearted? && "bg-primary/20 text-primary border border-primary/30",
            !@reactions.hearted? &&
              "bg-base-content/[0.04] text-base-content/60 hover:text-base-content hover:bg-base-content/[0.08]"
          ]}
        >
          <.icon name="hero-heart" class={["size-3.5", @reactions.hearted? && "fill-current"]} />
          <span>{@reactions.heart_count}</span>
        </button>

        <button
          type="button"
          phx-click="toggle_reaction"
          phx-value-kind="torch"
          phx-value-post_id={@post.id}
          class={[
            "flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold tracking-wide transition-all active:scale-95",
            @reactions.torched? && "bg-rose-500/20 text-rose-400 border border-rose-500/30",
            !@reactions.torched? &&
              "bg-base-content/[0.04] text-base-content/60 hover:text-base-content hover:bg-base-content/[0.08]"
          ]}
        >
          <.icon name="hero-fire" class={["size-3.5", @reactions.torched? && "fill-current"]} />
          <span>{@reactions.torch_count}</span>
        </button>

        <.comment_button post_id={@post.id} count={@comment_count} />
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoplayCarousel">
      export default {
        mounted() {
          this.index = 0;
          this.slides = Array.from(this.el.querySelectorAll(".carousel-slide"));
          this.dots = Array.from(this.el.querySelectorAll(".carousel-dot"));
          this.counter = this.el.querySelector(".carousel-counter");
          this.count = this.slides.length;
          this.timer = null;

          const show = (idx) => {
            this.index = ((idx % this.count) + this.count) % this.count;
            this.slides.forEach((slide, i) => {
              slide.classList.toggle("opacity-100", i === this.index);
              slide.classList.toggle("z-10", i === this.index);
              slide.classList.toggle("opacity-0", i !== this.index);
            });
            this.dots.forEach((dot, i) => {
              dot.classList.toggle("bg-white", i === this.index);
              dot.classList.toggle("bg-white/40", i !== this.index);
            });
            if (this.counter) this.counter.textContent = `${this.index + 1}/${this.count}`;
          };

          const next = () => show(this.index + 1);
          const prev = () => show(this.index - 1);

          const startAutoplay = () => {
            if (this.timer || this.count <= 1) return;
            this.timer = setInterval(next, 3000);
          };
          const stopAutoplay = () => {
            clearInterval(this.timer);
            this.timer = null;
          };
          this.stopAutoplay = stopAutoplay;

          this.el.querySelector(".carousel-prev")?.addEventListener("click", e => {
            e.preventDefault();
            e.stopPropagation();
            prev();
          });
          this.el.querySelector(".carousel-next")?.addEventListener("click", e => {
            e.preventDefault();
            e.stopPropagation();
            next();
          });

          this.observer = new IntersectionObserver(entries => {
            entries.forEach(entry => {
              if (entry.isIntersecting && entry.intersectionRatio >= 0.6) startAutoplay();
              else stopAutoplay();
            });
          }, { threshold: [0, 0.6, 1] });
          this.observer.observe(this.el);
        },
        destroyed() {
          this.observer?.disconnect();
          this.stopAutoplay?.();
        }
      };
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoplayAudio">
      export default {
        mounted() {
          const src = this.el.dataset.src;
          if (!src) return;

          this.audio = new Audio(src);
          this.userPaused = false;

          const totalMs = parseInt(this.el.dataset.durationMs || "0", 10);
          const playIcon = this.el.querySelector(".audio-icon-play");
          const pauseIcon = this.el.querySelector(".audio-icon-pause");
          const fill = this.el.querySelector(".audio-fill");
          const time = this.el.querySelector(".audio-time");
          const toggle = this.el.querySelector(".audio-toggle");

          const format = seconds => {
            const total = Math.max(0, Math.round(seconds));
            return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
          };

          const showPlaying = playing => {
            playIcon?.classList.toggle("hidden", playing);
            pauseIcon?.classList.toggle("hidden", !playing);
          };

          this.audio.addEventListener("play", () => {
            showPlaying(true);
            window.dispatchEvent(new CustomEvent("agora:audio-play", { detail: { id: this.el.id } }));
          });
          this.audio.addEventListener("pause", () => showPlaying(false));
          this.audio.addEventListener("ended", () => {
            showPlaying(false);
            this.userPaused = true;
          });
          this.audio.addEventListener("timeupdate", () => {
            if (this.audio.duration && fill) {
              fill.style.width = `${(this.audio.currentTime / this.audio.duration) * 100}%`;
            }
            if (time) {
              time.textContent = totalMs
                ? `${format(this.audio.currentTime)} / ${format(totalMs / 1000)}`
                : format(this.audio.currentTime);
            }
          });

          this.onOtherPlay = e => {
            if (e.detail.id !== this.el.id) this.audio.pause();
          };
          window.addEventListener("agora:audio-play", this.onOtherPlay);

          toggle?.addEventListener("click", e => {
            e.preventDefault();
            e.stopPropagation();
            if (this.audio.paused) {
              this.userPaused = false;
              this.audio.play().catch(() => {});
            } else {
              this.userPaused = true;
              this.audio.pause();
            }
          });

          this.observer = new IntersectionObserver(entries => {
            entries.forEach(entry => {
              if (entry.isIntersecting && entry.intersectionRatio >= 0.6) {
                if (!this.userPaused) this.audio.play().catch(() => {});
              } else {
                this.audio.pause();
              }
            });
          }, { threshold: [0, 0.6, 1] });
          this.observer.observe(this.el);
        },
        destroyed() {
          this.observer?.disconnect();
          if (this.onOtherPlay) window.removeEventListener("agora:audio-play", this.onOtherPlay);
          this.audio?.pause();
        }
      };
    </script>
    """
  end

  defp kind_label(:audio), do: "Audio"
  defp kind_label(:image_set), do: "Photos"
  defp kind_label(:tiding), do: "Tiding"
  defp kind_label(_), do: "Post"

  defp audio_url(%{media: media}) do
    Enum.find_value(media, fn m -> m.kind == :audio && m.url end)
  end

  @doc """
  Short relative time for a feed card's timestamp.
  """
  def time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "now"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86_400 -> "#{div(diff, 3600)}h"
      diff < 604_800 -> "#{div(diff, 86_400)}d"
      diff < 2_419_200 -> "#{div(diff, 604_800)}w"
      true -> Calendar.strftime(datetime, "%b %-d")
    end
  end

  @doc """
  A circular, kind-colored post preview.
  """
  attr :post, :any, required: true
  attr :navigate, :any, required: true

  def post_circle(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="flex items-center justify-center size-12 rounded-full bg-gradient-to-tr from-primary to-rose-600 text-white shrink-0
             transition-all duration-200 hover:scale-105 active:scale-95 shadow border border-white/20"
    >
      <.icon name={row_icon(@post.kind)} class="size-5" />
    </.link>
    """
  end

  @doc "The leading '+' circle in that same strip — starts a new post."
  attr :rest, :global

  def new_post_circle(assigns) do
    ~H"""
    <button
      type="button"
      class="flex items-center justify-center size-12 rounded-full border border-dashed border-primary/50 text-primary shrink-0
             transition-all duration-200 hover:bg-primary/10 hover:border-primary active:scale-95"
      {@rest}
    >
      <.icon name="hero-plus" class="size-5" />
    </button>
    """
  end

  @doc """
  The comment button + count shown on a feed card / post detail's reaction
  bar. Fires `open_comments` on the server (to load that post's comments)
  and shows the shared `#comment-modal` on the client in the same click,
  so the modal opens instantly instead of waiting on a round-trip.
  """
  attr :post_id, :any, required: true
  attr :count, :integer, required: true

  def comment_button(assigns) do
    ~H"""
    <button
      type="button"
      id={"comment-button-#{@post_id}"}
      phx-click={JS.push("open_comments", value: %{post_id: @post_id}) |> show_modal("comment-modal")}
      class="flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold tracking-wide transition-all active:scale-95
             bg-base-content/[0.04] text-base-content/60 hover:text-base-content hover:bg-base-content/[0.08]"
    >
      <.icon name="hero-chat-bubble-left" class="size-3.5" />
      <span>{@count}</span>
    </button>
    """
  end

  @doc """
  The single shared comment modal, driven by whichever post the viewer
  most recently opened. One instance lives at the bottom of FeedLive and
  PostLive.Show — `#comment-modal` is a stable DOM id so `show_modal/hide_modal`
  JS commands can always find it, even before any post has been opened.
  """
  attr :post_id, :any, default: nil
  attr :comments, :list, default: []
  attr :current_scope, :any, default: nil

  def comment_modal(assigns) do
    ~H"""
    <.modal id="comment-modal" on_cancel={JS.push("close_comments")}>
      <div class="flex flex-col max-h-[75vh] sm:max-h-[70vh]">
        <h3 class="font-display text-base font-bold text-base-content mb-4 flex items-center gap-2 pr-8">
          <.icon name="hero-chat-bubble-left-right" class="size-4 text-primary" /> Comments
        </h3>

        <div id="comment-list" class="flex-1 overflow-y-auto space-y-3 pr-1 -mr-1 custom-scrollbar">
          <div :for={comment <- @comments} class="flex items-start gap-2.5">
            <.avatar
              avatar_url={comment.user.profile.avatar_url}
              display_name={comment.user.profile.display_name}
              size="size-8"
            />
            <div class="flex-1 min-w-0 rounded-2xl well px-3.5 py-2.5 border border-base-content/[0.05]">
              <div class="flex items-baseline gap-2">
                <span class="text-xs font-bold text-base-content truncate">
                  {comment.user.profile.display_name}
                </span>
                <span class="text-[10px] text-base-content/40 shrink-0">{time_ago(comment.inserted_at)}</span>
              </div>
              <p class="text-sm text-base-content/90 leading-relaxed whitespace-pre-line mt-0.5 break-words">
                {comment.body}
              </p>
            </div>
          </div>

          <p :if={@comments == []} class="text-center text-xs text-base-content/40 py-10">
            No comments yet. Be the first to say something.
          </p>
        </div>

        <form
          :if={@current_scope}
          id="comment-form"
          phx-submit="add_comment"
          phx-hook=".CommentForm"
          class="flex items-center gap-2 pt-4 mt-3 border-t border-base-content/10"
        >
          <input type="hidden" name="post_id" value={@post_id} />
          <input
            type="text"
            name="body"
            placeholder="Write a comment…"
            autocomplete="off"
            maxlength="2000"
            required
            class="input input-sm flex-1 well border-base-content/10 focus:border-primary focus:ring-1 focus:ring-primary rounded-full text-sm"
          />
          <button
            type="submit"
            class="btn btn-sm btn-circle btn-primary active:scale-95 transition-all shrink-0"
          >
            <.icon name="hero-paper-airplane" class="size-4" />
          </button>
        </form>

        <.link
          :if={!@current_scope}
          navigate={~p"/users/log-in"}
          class="block text-center text-xs font-semibold text-primary py-4 mt-3 border-t border-base-content/10"
        >
          Log in to join the conversation
        </.link>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CommentForm">
        export default {
          mounted() {
            this.handleEvent("reset-comment-form", () => this.el.reset());
          }
        };
      </script>
    </.modal>
    """
  end

  @doc """
  The broadcaster's live audio effects control panel — gain, noise gate,
  4-band EQ, compressor, reverb, and limiter, all adjustable while a
  Gathering is live. A single form with `phx-change="update_effect"`;
  every control's `name` is a bracketed path (`compressor[ratio]`,
  `noise_gate[enabled]`, ...) so Phoenix's own form-param parsing
  reassembles the exact nested shape `Agora.Media.Audio.Params` expects,
  and `Agora.Media.Audio.Params.merge/2` (already exercised against
  string-keyed, partial, and even hostile input in
  `params_test.exs`) does the rest — no bespoke parsing needed here.
  """
  attr :params, :map, required: true

  def effects_panel(assigns) do
    ~H"""
    <div class="rounded-2xl bg-base-200/60 border border-base-content/[0.06] p-5 space-y-4">
      <div class="flex items-center justify-between border-b border-base-content/[0.06] pb-3">
        <div>
          <h3 class="font-display text-base font-bold text-base-content">Live Audio Studio</h3>
          <p class="text-xs text-base-content/50">
            Gain, EQ, compression, reverb &amp; limiting — adjustable while you're live
          </p>
        </div>
        <.icon name="hero-adjustments-horizontal" class="size-5 text-primary" />
      </div>

      <form id="effects-form" phx-change="update_effect" class="space-y-3">
        <.range_row
          label="Input Gain"
          name="input_gain_db"
          value={@params.input_gain_db}
          min={-24.0}
          max={24.0}
          step={0.5}
          unit=" dB"
        />

        <.effect_section
          title="Noise Gate"
          icon="hero-speaker-x-mark"
          enabled_name="noise_gate[enabled]"
          enabled={@params.noise_gate.enabled}
        >
          <.range_row
            label="Threshold"
            name="noise_gate[threshold_db]"
            value={@params.noise_gate.threshold_db}
            min={-80.0}
            max={0.0}
            step={1.0}
            unit=" dB"
          />
          <.range_row
            label="Attack"
            name="noise_gate[attack_ms]"
            value={@params.noise_gate.attack_ms}
            min={0.0}
            max={200.0}
            step={0.5}
            unit=" ms"
          />
          <.range_row
            label="Release"
            name="noise_gate[release_ms]"
            value={@params.noise_gate.release_ms}
            min={5.0}
            max={2000.0}
            step={5.0}
            unit=" ms"
          />
          <.range_row
            label="Hold"
            name="noise_gate[hold_ms]"
            value={@params.noise_gate.hold_ms}
            min={0.0}
            max={1000.0}
            step={5.0}
            unit=" ms"
          />
          <.range_row
            label="Floor"
            name="noise_gate[range_db]"
            value={@params.noise_gate.range_db}
            min={-90.0}
            max={0.0}
            step={1.0}
            unit=" dB"
          />
        </.effect_section>

        <div class="rounded-xl bg-base-content/[0.03] border border-base-content/[0.05] p-4 space-y-3">
          <div class="flex items-center gap-2">
            <.icon name="hero-adjustments-vertical" class="size-4 text-primary" />
            <span class="text-xs font-bold text-base-content/90">Equalizer</span>
          </div>

          <.eq_band
            title="High-pass (rumble cut)"
            enabled_name="eq[highpass][enabled]"
            enabled={@params.eq.highpass.enabled}
          >
            <.range_row
              label="Frequency"
              name="eq[highpass][freq]"
              value={@params.eq.highpass.freq}
              min={20.0}
              max={500.0}
              step={5.0}
              unit=" Hz"
            />
            <.range_row
              label="Q"
              name="eq[highpass][q]"
              value={@params.eq.highpass.q}
              min={0.3}
              max={5.0}
              step={0.05}
              unit=""
            />
          </.eq_band>

          <.eq_band
            title="Low Shelf"
            enabled_name="eq[low_shelf][enabled]"
            enabled={@params.eq.low_shelf.enabled}
          >
            <.range_row
              label="Frequency"
              name="eq[low_shelf][freq]"
              value={@params.eq.low_shelf.freq}
              min={20.0}
              max={1000.0}
              step={10.0}
              unit=" Hz"
            />
            <.range_row
              label="Gain"
              name="eq[low_shelf][gain_db]"
              value={@params.eq.low_shelf.gain_db}
              min={-15.0}
              max={15.0}
              step={0.5}
              unit=" dB"
            />
          </.eq_band>

          <.eq_band
            title="Mid Peak"
            enabled_name="eq[mid_peak][enabled]"
            enabled={@params.eq.mid_peak.enabled}
          >
            <.range_row
              label="Frequency"
              name="eq[mid_peak][freq]"
              value={@params.eq.mid_peak.freq}
              min={150.0}
              max={8000.0}
              step={10.0}
              unit=" Hz"
            />
            <.range_row
              label="Gain"
              name="eq[mid_peak][gain_db]"
              value={@params.eq.mid_peak.gain_db}
              min={-15.0}
              max={15.0}
              step={0.5}
              unit=" dB"
            />
            <.range_row
              label="Q"
              name="eq[mid_peak][q]"
              value={@params.eq.mid_peak.q}
              min={0.3}
              max={8.0}
              step={0.1}
              unit=""
            />
          </.eq_band>

          <.eq_band
            title="High Shelf (presence/air)"
            enabled_name="eq[high_shelf][enabled]"
            enabled={@params.eq.high_shelf.enabled}
            last?={true}
          >
            <.range_row
              label="Frequency"
              name="eq[high_shelf][freq]"
              value={@params.eq.high_shelf.freq}
              min={1500.0}
              max={18_000.0}
              step={100.0}
              unit=" Hz"
            />
            <.range_row
              label="Gain"
              name="eq[high_shelf][gain_db]"
              value={@params.eq.high_shelf.gain_db}
              min={-15.0}
              max={15.0}
              step={0.5}
              unit=" dB"
            />
          </.eq_band>
        </div>

        <.effect_section
          title="Compressor"
          icon="hero-arrows-pointing-in"
          enabled_name="compressor[enabled]"
          enabled={@params.compressor.enabled}
        >
          <.range_row
            label="Threshold"
            name="compressor[threshold_db]"
            value={@params.compressor.threshold_db}
            min={-60.0}
            max={0.0}
            step={1.0}
            unit=" dB"
          />
          <.range_row
            label="Ratio"
            name="compressor[ratio]"
            value={@params.compressor.ratio}
            min={1.0}
            max={20.0}
            step={0.5}
            unit=":1"
          />
          <.range_row
            label="Attack"
            name="compressor[attack_ms]"
            value={@params.compressor.attack_ms}
            min={0.0}
            max={200.0}
            step={0.5}
            unit=" ms"
          />
          <.range_row
            label="Release"
            name="compressor[release_ms]"
            value={@params.compressor.release_ms}
            min={5.0}
            max={2000.0}
            step={5.0}
            unit=" ms"
          />
          <.range_row
            label="Knee"
            name="compressor[knee_db]"
            value={@params.compressor.knee_db}
            min={0.0}
            max={24.0}
            step={0.5}
            unit=" dB"
          />
          <.range_row
            label="Makeup Gain"
            name="compressor[makeup_gain_db]"
            value={@params.compressor.makeup_gain_db}
            min={0.0}
            max={24.0}
            step={0.5}
            unit=" dB"
          />
        </.effect_section>

        <.effect_section
          title="Reverb"
          icon="hero-speaker-wave"
          enabled_name="reverb[enabled]"
          enabled={@params.reverb.enabled}
        >
          <.range_row
            label="Mix"
            name="reverb[mix]"
            value={@params.reverb.mix}
            min={0.0}
            max={0.6}
            step={0.01}
            unit=""
          />
          <.range_row
            label="Room Size"
            name="reverb[room_size]"
            value={@params.reverb.room_size}
            min={0.0}
            max={1.0}
            step={0.01}
            unit=""
          />
          <.range_row
            label="Damping"
            name="reverb[damping]"
            value={@params.reverb.damping}
            min={0.0}
            max={1.0}
            step={0.01}
            unit=""
          />
        </.effect_section>

        <.effect_section
          title="Limiter"
          icon="hero-shield-check"
          enabled_name="limiter[enabled]"
          enabled={@params.limiter.enabled}
        >
          <.range_row
            label="Ceiling"
            name="limiter[ceiling_db]"
            value={@params.limiter.ceiling_db}
            min={-12.0}
            max={0.0}
            step={0.5}
            unit=" dB"
          />
          <.range_row
            label="Attack"
            name="limiter[attack_ms]"
            value={@params.limiter.attack_ms}
            min={0.0}
            max={50.0}
            step={0.5}
            unit=" ms"
          />
          <.range_row
            label="Release"
            name="limiter[release_ms]"
            value={@params.limiter.release_ms}
            min={5.0}
            max={1000.0}
            step={5.0}
            unit=" ms"
          />
        </.effect_section>
      </form>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :value, :float, required: true
  attr :min, :float, required: true
  attr :max, :float, required: true
  attr :step, :float, default: 0.1
  attr :unit, :string, default: ""

  defp range_row(assigns) do
    ~H"""
    <div class="space-y-1">
      <div class="flex items-center justify-between text-[11px]">
        <span class="font-semibold text-base-content/70">{@label}</span>
        <span class="font-mono text-primary">{format_range_value(@value)}{@unit}</span>
      </div>
      <input
        type="range"
        name={@name}
        value={@value}
        min={@min}
        max={@max}
        step={@step}
        phx-debounce="150"
        class="range range-primary range-xs w-full"
      />
    </div>
    """
  end

  defp format_range_value(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 2)
  end

  defp format_range_value(value), do: to_string(value)

  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :enabled_name, :string, default: nil
  attr :enabled, :boolean, default: true
  slot :inner_block, required: true

  defp effect_section(assigns) do
    ~H"""
    <div class="rounded-xl bg-base-content/[0.03] border border-base-content/[0.05] p-4 space-y-3">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <.icon name={@icon} class="size-4 text-primary" />
          <span class="text-xs font-bold text-base-content/90">{@title}</span>
        </div>
        <.enabled_toggle :if={@enabled_name} name={@enabled_name} enabled={@enabled} />
      </div>
      <div class={["space-y-3", !@enabled && "opacity-40 pointer-events-none"]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :enabled_name, :string, required: true
  attr :enabled, :boolean, required: true
  attr :last?, :boolean, default: false
  slot :inner_block, required: true

  defp eq_band(assigns) do
    ~H"""
    <div class={["space-y-2 pb-3", !@last? && "border-b border-base-content/[0.05]"]}>
      <div class="flex items-center justify-between">
        <span class="text-[11px] font-bold uppercase tracking-wider text-base-content/50">{@title}</span>
        <.enabled_toggle name={@enabled_name} enabled={@enabled} />
      </div>
      <div class={["space-y-2", !@enabled && "opacity-40 pointer-events-none"]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :enabled, :boolean, required: true

  defp enabled_toggle(assigns) do
    ~H"""
    <label class="inline-flex items-center cursor-pointer">
      <input type="hidden" name={@name} value="false" />
      <input
        type="checkbox"
        name={@name}
        value="true"
        checked={@enabled}
        class="toggle toggle-primary toggle-xs"
      />
    </label>
    """
  end
end
