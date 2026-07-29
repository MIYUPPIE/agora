defmodule AgoraWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use AgoraWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen mesh-bg flex flex-col font-sans">
      <!-- Top Navigation Header -->
      <header class="sticky top-0 z-30 bg-base-100/80 backdrop-blur-xl border-b border-base-content/[0.06] px-4 sm:px-6 lg:px-8 py-3 transition-all">
        <div class="mx-auto max-w-5xl flex items-center justify-between gap-4">
          <!-- Logo & Brand -->
          <div class="flex items-center gap-4 sm:gap-6">
            <.link navigate={~p"/"} class="shrink-0">
              <.logo size="size-7 sm:size-8" text_size="text-base sm:text-lg" />
            </.link>

            <!-- Desktop Nav Links -->
            <nav class="hidden md:flex items-center gap-1 pl-4 border-l border-base-content/10">
              <.link
                navigate={~p"/feed"}
                class="flex items-center gap-2 px-3 py-1.5 rounded-lg font-medium text-sm text-base-content/70 hover:text-base-content hover:bg-base-content/[0.06] transition-all"
              >
                <.icon name="hero-rectangle-stack" class="size-4 text-primary" /> Feed
              </.link>
              <.link
                navigate={~p"/gatherings"}
                class="flex items-center gap-2 px-3 py-1.5 rounded-lg font-medium text-sm text-base-content/70 hover:text-base-content hover:bg-base-content/[0.06] transition-all"
              >
                <.icon name="hero-signal" class="size-4 text-primary" /> Live Now
              </.link>
              <.link
                :if={@current_scope}
                navigate={~p"/profile/#{@current_scope.user.id}"}
                class="flex items-center gap-2 px-3 py-1.5 rounded-lg font-medium text-sm text-base-content/70 hover:text-base-content hover:bg-base-content/[0.06] transition-all"
              >
                <.icon name="hero-user" class="size-4 text-primary" /> Profile
              </.link>
            </nav>
          </div>

          <!-- Actions & User Section -->
          <div class="flex items-center gap-3">
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

            <div :if={@current_scope} class="flex items-center gap-3">
              <.link
                navigate={~p"/gatherings/new"}
                class="hidden sm:inline-flex btn btn-primary btn-sm font-bold text-xs active:scale-95 transition-all shadow-lg rounded-full px-4"
              >
                <.icon name="hero-microphone" class="size-4" /> Go Live
              </.link>

              <.link
                navigate={~p"/profile/#{@current_scope.user.id}"}
                class="flex items-center justify-center size-8 rounded-full bg-primary/20 text-primary font-bold text-xs hover:bg-primary/30 transition-colors"
                title="Profile"
              >
                {initial(@current_scope.user.email)}
              </.link>

              <.link
                navigate={~p"/users/settings"}
                class="btn btn-ghost btn-xs text-base-content/60 hover:text-base-content"
                title="Settings"
              >
                <.icon name="hero-cog-6-tooth" class="size-4" />
              </.link>

              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="btn btn-ghost btn-xs text-base-content/60 hover:text-base-content"
                title="Log Out"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
              </.link>
            </div>

            <div :if={!@current_scope} class="flex items-center gap-2">
              <.link
                navigate={~p"/users/log-in"}
                class="btn btn-ghost btn-sm font-semibold text-xs text-base-content/80 hover:text-base-content"
              >
                Log In
              </.link>
              <.link
                navigate={~p"/users/register"}
                class="btn btn-primary btn-sm font-bold text-xs text-white rounded-full px-4 active:scale-95 transition-all"
              >
                Sign Up
              </.link>
            </div>
          </div>
        </div>
      </header>

      <!-- Main Content Stage -->
      <main class="flex-1 max-w-5xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-6 pb-24 md:pb-8">
        {render_slot(@inner_block)}
      </main>

      <!-- Global Footer -->
      <footer class="mt-auto border-t border-base-content/[0.05] py-6 px-4 text-xs text-base-content/40">
        <div class="max-w-5xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-3">
          <div class="flex items-center gap-2">
            <img src={~p"/images/agora-mark.png"} class="size-4 opacity-50" alt="Agora" />
            <span class="font-display font-bold text-base-content/70">AGORA</span>
            <span>&copy; {Date.utc_today().year} Audio-First Social</span>
          </div>
          <div class="flex items-center gap-4 text-base-content/50">
            <.link navigate={~p"/gatherings"} class="hover:text-base-content transition-colors">Live Gatherings</.link>
            <.link navigate={~p"/feed"} class="hover:text-base-content transition-colors">Feed</.link>
          </div>
        </div>
      </footer>

      <!-- Mobile Bottom Navigation Bar -->
      <nav
        class="md:hidden fixed bottom-0 left-0 right-0 z-40 bg-base-100/95 backdrop-blur-xl border-t border-base-content/[0.06] px-6 py-2 flex items-center justify-around shadow-2xl"
        style="padding-bottom: max(0.5rem, env(safe-area-inset-bottom))"
      >
        <.link
          navigate={~p"/feed"}
          class="flex flex-col items-center gap-1 text-base-content/60 hover:text-primary active:scale-95 transition-all"
        >
          <.icon name="hero-rectangle-stack" class="size-5" />
          <span class="text-[10px] font-medium">Feed</span>
        </.link>
        <.link
          navigate={~p"/gatherings"}
          class="flex flex-col items-center gap-1 text-base-content/60 hover:text-primary active:scale-95 transition-all"
        >
          <.icon name="hero-signal" class="size-5" />
          <span class="text-[10px] font-medium">Live</span>
        </.link>
        <.link
          navigate={if @current_scope, do: ~p"/gatherings/new", else: ~p"/users/log-in"}
          class="flex items-center justify-center size-11 rounded-full bg-primary text-white active:scale-90 -mt-5 border-2 border-base-100 shadow-lg transition-transform"
        >
          <.icon name="hero-microphone" class="size-5" />
        </.link>
        <.link
          :if={@current_scope}
          navigate={~p"/profile/#{@current_scope.user.id}"}
          class="flex flex-col items-center gap-1 text-base-content/60 hover:text-primary active:scale-95 transition-all"
        >
          <.icon name="hero-user" class="size-5" />
          <span class="text-[10px] font-medium">Profile</span>
        </.link>
        <.link
          :if={@current_scope}
          navigate={~p"/users/settings"}
          class="flex flex-col items-center gap-1 text-base-content/60 hover:text-primary active:scale-95 transition-all"
        >
          <.icon name="hero-cog-6-tooth" class="size-5" />
          <span class="text-[10px] font-medium">Settings</span>
        </.link>
        <.link
          :if={!@current_scope}
          navigate={~p"/users/log-in"}
          class="flex flex-col items-center gap-1 text-base-content/60 hover:text-primary active:scale-95 transition-all"
        >
          <.icon name="hero-arrow-right-on-rectangle" class="size-5" />
          <span class="text-[10px] font-medium">Log In</span>
        </.link>
      </nav>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  defp initial(email) when is_binary(email) do
    email |> String.trim() |> String.first() |> Kernel.||("U") |> String.upcase()
  end

  defp initial(_), do: "U"

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="fixed top-16 right-4 z-50 space-y-2 max-w-sm">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
