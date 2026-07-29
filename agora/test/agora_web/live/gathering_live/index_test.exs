defmodule AgoraWeb.GatheringLive.IndexTest do
  use AgoraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Agora.AccountsFixtures

  alias Agora.Gatherings

  test "lists only gatherings that are currently live", %{conn: conn} do
    viewer = user_fixture()
    broadcaster = user_fixture()

    {:ok, live_gathering} = Gatherings.create_gathering(broadcaster.id, %{"title" => "Live one"})
    {:ok, scheduled} = Gatherings.create_gathering(broadcaster.id, %{"title" => "Not yet"})
    :ok = Gatherings.mark_live!(live_gathering.id)

    {:ok, _lv, html} = live(log_in_user(conn, viewer), ~p"/gatherings")

    assert html =~ "Live one"
    refute html =~ "Not yet"
    refute html =~ scheduled.title
  end

  test "shows an empty state when nobody is live", %{conn: conn} do
    viewer = user_fixture()
    {:ok, _lv, html} = live(log_in_user(conn, viewer), ~p"/gatherings")
    assert html =~ "No one is live right now"
  end

  test "renders gatherings list for anonymous visitors", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/gatherings")
    assert html =~ "Live now"
  end
end
