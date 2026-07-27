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
    <div class="text-center">
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
    <div class={[@size, "rounded-full overflow-hidden shrink-0"]}>
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
      class="flex flex-col items-center gap-1 rounded-lg bg-black/40 px-2 py-2 text-white hover:bg-black/60 transition-colors"
      {@rest}
    >
      <.icon name={@icon} class="size-5" />
      <span class="text-[11px] font-medium leading-tight text-center">{@label}</span>
    </button>
    """
  end
end
