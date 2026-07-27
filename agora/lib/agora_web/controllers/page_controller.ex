defmodule AgoraWeb.PageController do
  use AgoraWeb, :controller

  @doc """
  Root path: signed-in users land on their own profile hub, everyone
  else on the login screen.
  """
  def home(conn, _params) do
    if scope = conn.assigns[:current_scope] do
      redirect(conn, to: ~p"/profile/#{scope.user.id}")
    else
      redirect(conn, to: ~p"/users/log-in")
    end
  end
end
