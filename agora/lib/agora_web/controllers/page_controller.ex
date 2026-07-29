defmodule AgoraWeb.PageController do
  use AgoraWeb, :controller

  @doc """
  Root path: signed-in users land on their feed, same as Instagram's home
  tab — not their own profile. Everyone else gets an actual public landing
  page (see PageHTML.home/1) instead of being bounced straight to a bare
  login form — a first-time visitor should see what Agora even is before
  being asked to sign up.
  """
  def home(conn, _params) do
    if conn.assigns[:current_scope] do
      redirect(conn, to: ~p"/feed")
    else
      render(conn, :home)
    end
  end
end
