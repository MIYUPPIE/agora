defmodule AgoraWeb.PageControllerTest do
  use AgoraWeb.ConnCase

  test "GET / shows the public landing page when signed out", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "AGORA"
    assert html_response(conn, 200) =~ ~p"/users/register"
    assert html_response(conn, 200) =~ ~p"/users/log-in"
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
