defmodule AgoraWeb.NotificationsLiveTest do
  use AgoraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Agora.AccountsFixtures

  alias Agora.{Notifications, Posts, Profiles, Social}

  setup do
    %{alice: user_fixture(), bob: user_fixture()}
  end

  test "redirects an anonymous visitor to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/notifications")
    assert to == ~p"/users/log-in"
  end

  test "shows an empty state with no notifications", %{conn: conn, alice: alice} do
    {:ok, _lv, html} = live(log_in_user(conn, alice), ~p"/notifications")
    assert html =~ "No notifications yet."
  end

  test "renders a cling notification with the actor's name and a link to their profile", %{
    conn: conn,
    alice: alice,
    bob: bob
  } do
    {:ok, _} = Social.cling(bob.id, alice.id)

    {:ok, _lv, html} = live(log_in_user(conn, alice), ~p"/notifications")

    bob_profile = Profiles.get_or_create!(bob)
    assert html =~ bob_profile.display_name
    assert html =~ "started clinging to you"
    assert html =~ ~p"/profile/#{bob.id}"
  end

  test "renders a comment notification linking to the post", %{conn: conn, alice: alice, bob: bob} do
    {:ok, post} = Posts.create_tiding(alice.id, %{"body" => "hello"})
    {:ok, _} = Posts.add_comment(bob.id, post.id, "Amen!")

    {:ok, _lv, html} = live(log_in_user(conn, alice), ~p"/notifications")

    assert html =~ "commented on your post"
    assert html =~ ~p"/posts/#{post.id}"
  end

  test "renders a reaction notification with the right verb per kind", %{
    conn: conn,
    alice: alice,
    bob: bob
  } do
    {:ok, post} = Posts.create_tiding(alice.id, %{"body" => "hello"})
    :ok = Posts.toggle_reaction(bob.id, post.id, :torch)

    {:ok, _lv, html} = live(log_in_user(conn, alice), ~p"/notifications")

    assert html =~ "torched your post"
  end

  test "opening the page marks all notifications read and clears the unread count", %{
    conn: conn,
    alice: alice,
    bob: bob
  } do
    {:ok, _} = Social.cling(bob.id, alice.id)
    assert Notifications.unread_count(alice.id) == 1

    {:ok, _lv, _html} = live(log_in_user(conn, alice), ~p"/notifications")

    assert Notifications.unread_count(alice.id) == 0
  end

  test "the nav bell shows the unread count elsewhere in the app", %{
    conn: conn,
    alice: alice,
    bob: bob
  } do
    {:ok, _} = Social.cling(bob.id, alice.id)

    {:ok, _lv, html} = live(log_in_user(conn, alice), ~p"/feed")

    assert html =~ ~p"/notifications"
    assert html =~ ~r/>\s*1\s*</
  end
end
