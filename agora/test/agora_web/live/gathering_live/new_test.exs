defmodule AgoraWeb.GatheringLive.NewTest do
  use AgoraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Agora.AccountsFixtures

  alias Agora.Gatherings

  test "creating a gathering shows the ingest URL and a waiting state", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

    html =
      lv
      |> form("form", gathering: %{title: "Sunday service"})
      |> render_submit()

    assert html =~ "rtmp://"
    assert html =~ "Waiting for your encoder to connect"

    gathering = Gatherings.get_by_stream_key(extract_stream_key(html))
    assert gathering.title == "Sunday service"
    assert gathering.status == :scheduled
  end

  test "flips to the listener view automatically once the encoder connects (goes live)", %{
    conn: conn
  } do
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

    assert_redirect(lv, ~p"/gatherings/#{gathering.id}")
  end

  defp extract_stream_key(html) do
    [_, key] = Regex.run(~r{rtmp://[^/]+/live/([^\s<]+)}, html)
    key
  end
end
