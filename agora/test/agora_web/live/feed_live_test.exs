defmodule AgoraWeb.FeedLiveTest do
  use AgoraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Agora.AccountsFixtures

  alias Agora.{Posts, Social}

  test "shows an empty state when clinging to nobody yet", %{conn: conn} do
    user = user_fixture()
    {:ok, _lv, html} = live(log_in_user(conn, user), ~p"/feed")

    assert html =~ "No posts yet"
  end

  test "shows posts from people the user clings to, not from strangers", %{conn: conn} do
    viewer = user_fixture()
    clinged = user_fixture()
    stranger = user_fixture()
    {:ok, _} = Social.cling(viewer.id, clinged.id)

    {:ok, _} = Posts.create_tiding(clinged.id, %{"body" => "from someone I cling to"})
    {:ok, _} = Posts.create_tiding(stranger.id, %{"body" => "from a stranger"})

    {:ok, _lv, html} = live(log_in_user(conn, viewer), ~p"/feed")

    assert html =~ "from someone I cling to"
    refute html =~ "from a stranger"
  end

  test "a new post from someone clung-to appears live without a page reload", %{conn: conn} do
    viewer = user_fixture()
    clinged = user_fixture()
    {:ok, _} = Social.cling(viewer.id, clinged.id)

    {:ok, lv, html} = live(log_in_user(conn, viewer), ~p"/feed")
    refute html =~ "breaking tiding"

    {:ok, _post} = Posts.create_tiding(clinged.id, %{"body" => "breaking tiding"})

    assert render(lv) =~ "breaking tiding"
  end

  test "redirects anonymous visitors to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/feed")
  end
end
