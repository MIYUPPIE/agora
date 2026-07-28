defmodule AgoraWeb.AgoraComponents do
  @moduledoc """
  Agora-specific UI components — the domain look (stats, avatars, action
  pills) as opposed to `CoreComponents`' framework-generic building blocks.
  """
  use Phoenix.Component

  import AgoraWeb.CoreComponents, only: [icon: 1]

  attr :count, :integer, required: true
  attr :label, :string, required: true

  def stat(assigns) do
    ~H"""
    <div class="text-center rounded-box glass depth-card py-3 transition-transform hover:-translate-y-0.5">
      <div class="text-3xl font-bold text-white">{@count}</div>
      <div class="text-sm text-neutral-400">{@label}</div>
    </div>
    """
  end

  attr :avatar_url, :string, default: nil
  attr :display_name, :string, required: true
  attr :size, :string, default: "size-16"

  def avatar(assigns) do
    ~H"""
    <div class={[@size, "rounded-full overflow-hidden shrink-0 ring-2 ring-white/15 depth-card"]}>
      <img :if={@avatar_url} src={@avatar_url} alt={@display_name} class="w-full h-full object-cover" />
      <div
        :if={!@avatar_url}
        class="w-full h-full flex items-center justify-center bg-neutral text-neutral-content font-semibold"
      >
        {initial(@display_name)}
      </div>
    </div>
    """
  end

  defp initial(name) do
    name |> String.trim() |> String.first() |> Kernel.||("?") |> String.upcase()
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :rest, :global

  def action_pill(assigns) do
    ~H"""
    <button
      type="button"
      class="flex flex-col items-center gap-1 rounded-lg bg-black/30 backdrop-blur-sm px-2 py-2 text-white
             transition-all duration-200 hover:bg-black/50 hover:-translate-y-0.5 active:scale-95
             border border-white/5"
      {@rest}
    >
      <.icon name={@icon} class="size-5" />
      <span class="text-[11px] font-medium leading-tight text-center">{@label}</span>
    </button>
    """
  end

  @doc """
  A single compact feed/profile row: icon + title + muted meta, matching
  the mockup's list style. Full media (image, waveform+player) only
  shows on the post detail page.
  """
  attr :post, :any, required: true
  attr :navigate, :any, required: true

  def post_row(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="flex items-center gap-3 px-4 py-3 rounded-box glass depth-card rise-in
             transition-all duration-200 hover:-translate-y-0.5 hover:bg-white/[0.06] active:scale-[0.99]"
    >
      <.icon name={row_icon(@post.kind)} class="size-6 text-primary shrink-0" />
      <p class="text-sm text-base-content truncate">
        {row_title(@post)}<span :if={row_meta(@post)} class="text-base-content/50">: {row_meta(@post)}</span>
      </p>
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

  @doc """
  A circular, kind-colored post preview — the horizontal "recent
  activity" strip above the feed list on the profile hub.
  """
  attr :post, :any, required: true
  attr :navigate, :any, required: true

  def post_circle(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="flex items-center justify-center size-14 rounded-full bg-primary text-white shrink-0
             depth-glow transition-all duration-200 hover:-translate-y-1 hover:scale-105 active:scale-95"
    >
      <.icon name={row_icon(@post.kind)} class="size-6" />
    </.link>
    """
  end

  @doc "The leading '+' circle in that same strip — starts a new post."
  attr :rest, :global

  def new_post_circle(assigns) do
    ~H"""
    <button
      type="button"
      class="flex items-center justify-center size-14 rounded-full border-2 border-primary text-primary shrink-0
             transition-all duration-200 hover:bg-primary/10 hover:-translate-y-1 hover:scale-105 active:scale-95"
      {@rest}
    >
      <.icon name="hero-plus" class="size-6" />
    </button>
    """
  end
end
