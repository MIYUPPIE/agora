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

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header :if={@current_scope} class="navbar bg-base-200 px-4 sm:px-6 lg:px-8">
      <div class="flex-1 min-w-0">
        <a href="/" class="flex w-fit items-center gap-2 shrink-0">
          <img src={~p"/images/agora-mark.png"} width="28" alt="Agora" />
          <span class="text-sm font-semibold tracking-wide">AGORA</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex items-center gap-4 text-sm">
          <li class="hidden sm:block max-w-40 truncate text-base-content/60">
            {@current_scope.user.email}
          </li>
          <li><.link href={~p"/users/settings"} class="link link-hover">Settings</.link></li>
          <li>
            <.link href={~p"/users/log-out"} method="delete" class="link link-hover">
              Log out
            </.link>
          </li>
        </ul>
      </div>
    </header>

    <main class={["min-h-screen flex flex-col", @current_scope && "px-4 py-12 sm:px-6 lg:px-8"]}>
      <div class="mx-auto w-full max-w-2xl flex-1 flex flex-col justify-center">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
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
