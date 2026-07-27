defmodule AgoraWeb.PageController do
  use AgoraWeb, :controller

  @doc """
  Root path. Phase 2 will point signed-in users at the profile hub;
  until then, settings is the closest thing to a home base.
  """
  def home(conn, _params) do
    if conn.assigns[:current_scope] do
      redirect(conn, to: ~p"/users/settings")
    else
      redirect(conn, to: ~p"/users/log-in")
    end
  end
end
