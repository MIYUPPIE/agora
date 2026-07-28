defmodule AgoraWeb.PageHTML do
  @moduledoc """
  The public landing page (logged-out visitors at "/") — see
  PageController.home/2 and page_html/home.html.heex.
  """
  use AgoraWeb, :html

  embed_templates "page_html/*"
end
