defmodule AgoraWeb.PageControllerTest do
  use AgoraWeb.ConnCase

  test "GET / redirects to log in when signed out", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "GET / redirects to the profile hub when signed in", %{conn: conn} do
    user = Agora.AccountsFixtures.user_fixture()

    conn =
      conn
      |> log_in_user(user)
      |> get(~p"/")

    assert redirected_to(conn) == ~p"/profile/#{user.id}"
  end
end
