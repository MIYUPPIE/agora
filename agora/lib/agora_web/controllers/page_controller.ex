defmodule AgoraWeb.PageController do
  use AgoraWeb, :controller

  @doc """
  Root path: signed-in users land on their own profile hub. Everyone
  else gets an actual public landing page (see PageHTML.home/1) instead
  of being bounced straight to a bare login form — a first-time visitor
  should see what Agora even is before being asked to sign up.
  """
  def home(conn, _params) do
    if scope = conn.assigns[:current_scope] do
      redirect(conn, to: ~p"/profile/#{scope.user.id}")
    else
      render(conn, :home)
    end
  end
end
