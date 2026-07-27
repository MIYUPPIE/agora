defmodule AgoraWeb.GatheringLive.NewTest do
  use AgoraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Phoenix.ChannelTest
  import Agora.AccountsFixtures

  alias Agora.Gatherings
  alias AgoraWeb.{BroadcastChannel, UserSocket}

  test "creating a gathering shows the ingest URL and a waiting state", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

    html =
      lv
      |> form("form", gathering: %{title: "Sunday service"})
      |> render_submit()

    assert html =~ "rtmp://"
    assert html =~ "Waiting for your broadcast to start"

    gathering = Gatherings.get_by_stream_key(extract_stream_key(html))
    assert gathering.title == "Sunday service"
    assert gathering.status == :scheduled
  end

  test "shows a browser-broadcast panel with a token that actually authorizes that gathering", %{
    conn: conn
  } do
    user = user_fixture()
    {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

    html = lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

    assert html =~ ~s(id="browser-broadcast")
    assert html =~ ~s(phx-hook="BrowserBroadcast")

    gathering = hd(Agora.Repo.all(Agora.Gatherings.Gathering))
    [_, token] = Regex.run(~r/data-token="([^"]+)"/, html)

    assert {:ok, socket} = Phoenix.ChannelTest.connect(UserSocket, %{"token" => token})

    assert {:ok, _reply, _socket} =
             subscribe_and_join(socket, BroadcastChannel, "broadcast:#{gathering.id}", %{})
  end

  test "shows a live banner in place (with a new-tab listener link) instead of navigating away",
       %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

    lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

    gathering = hd(Agora.Repo.all(Agora.Gatherings.Gathering))
    Gatherings.mark_live!(gathering.id)

    Phoenix.PubSub.broadcast(
      Agora.PubSub,
      "gathering:#{gathering.id}",
      {:gathering_live, gathering.id}
    )

    html = render(lv)
    assert html =~ "You&#39;re live"
    assert html =~ ~s(target="_blank")
    assert html =~ ~p"/gatherings/#{gathering.id}"
    refute html =~ "Waiting for your broadcast to start"

    # Crucially: still on /gatherings/new, not navigated away — the
    # BrowserBroadcast hook's DOM (and any live mic stream) survives.
    assert html =~ ~s(id="browser-broadcast")
  end

  test "the live banner clears if the Gathering ends (broadcaster stopped, or disconnected)", %{
    conn: conn
  } do
    user = user_fixture()
    {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

    lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()
    gathering = hd(Agora.Repo.all(Agora.Gatherings.Gathering))

    Phoenix.PubSub.broadcast(
      Agora.PubSub,
      "gathering:#{gathering.id}",
      {:gathering_live, gathering.id}
    )

    assert render(lv) =~ "You&#39;re live"

    Phoenix.PubSub.broadcast(
      Agora.PubSub,
      "gathering:#{gathering.id}",
      {:gathering_ended, gathering.id}
    )

    html = render(lv)
    refute html =~ "You&#39;re live"
    assert html =~ "Waiting for your broadcast to start"
  end

  defp extract_stream_key(html) do
    [_, key] = Regex.run(~r{rtmp://[^/]+/live/([^\s<]+)}, html)
    key
  end
end
