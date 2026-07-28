defmodule AgoraWeb.FeedLiveTest do
  use AgoraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Agora.AccountsFixtures

  alias Agora.{Posts, Social}

  test "shows an empty state when clinging to nobody yet", %{conn: conn} do
    user = user_fixture()
    {:ok, _lv, html} = live(log_in_user(conn, user), ~p"/feed")

    assert html =~ "Your feed is quiet"
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

  test "reacting to a post in the feed toggles it without navigating away", %{conn: conn} do
    viewer = user_fixture()
    clinged = user_fixture()
    {:ok, _} = Social.cling(viewer.id, clinged.id)
    {:ok, post} = Posts.create_tiding(clinged.id, %{"body" => "react to me in the feed"})

    heart_selector = "button.text-primary[phx-value-post_id='#{post.id}'][phx-value-kind='heart']"

    {:ok, lv, _html} = live(log_in_user(conn, viewer), ~p"/feed")
    refute has_element?(lv, heart_selector)

    html =
      lv
      |> element("button[phx-value-post_id='#{post.id}'][phx-value-kind='heart']")
      |> render_click()

    # still rendering the feed (not navigated/redirected away) with the
    # reaction now reflected inline
    assert html =~ "react to me in the feed"
    assert has_element?(lv, heart_selector)
    assert Posts.reacted?(viewer.id, post.id, :heart)
    assert Posts.reaction_counts(post.id) == %{heart: 1, torch: 0}
  end

  test "redirects anonymous visitors to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/feed")
  end

  test "shows a live-now banner when a Clinger's Gathering goes live", %{conn: conn} do
    viewer = user_fixture()
    {:ok, lv, html} = live(log_in_user(conn, viewer), ~p"/feed")
    refute html =~ "is live now"

    send(lv.pid, {:gathering_live_notification, 42, "Jesse", "Sunday service"})

    html = render(lv)
    assert html =~ "Jesse is live now"
    assert html =~ "Sunday service"
    assert html =~ ~p"/gatherings/42"
  end
end
