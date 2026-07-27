defmodule AgoraWeb.ProfileLiveTest do
  use AgoraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Agora.AccountsFixtures

  alias Agora.{Profiles, Social}

  setup do
    %{alice: user_fixture(), bob: user_fixture()}
  end

  describe "viewing a profile" do
    test "anonymous visitor sees the hub with zeroed stats and a Cling button", %{
      conn: conn,
      bob: bob
    } do
      {:ok, _lv, html} = live(conn, ~p"/profile/#{bob.id}")

      profile = Profiles.get_or_create!(bob)
      assert html =~ profile.display_name
      assert html =~ "Cling"
      refute html =~ "hero-cog-6-tooth"
      assert html =~ ">0<"
    end

    test "owner sees settings gear and the account menu, not a Cling button", %{
      conn: conn,
      alice: alice
    } do
      {:ok, _lv, html} = live(log_in_user(conn, alice), ~p"/profile/#{alice.id}")

      assert html =~ ~p"/users/settings"
      assert html =~ ~p"/users/log-out"
      refute html =~ ">Cling<"
    end

    test "unknown profile id renders 404", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/profile/999999999")
      end
    end
  end

  describe "clinging" do
    test "an anonymous visitor clicking Cling is redirected to log in", %{conn: conn, bob: bob} do
      {:ok, lv, _html} = live(conn, ~p"/profile/#{bob.id}")

      {:error, {:live_redirect, %{to: to}}} =
        lv |> element("button", "Cling") |> render_click()

      assert to == ~p"/users/log-in"
    end

    test "a signed-in visitor can cling and uncling, with the button and stats flipping live", %{
      conn: conn,
      alice: alice,
      bob: bob
    } do
      {:ok, lv, html} = live(log_in_user(conn, alice), ~p"/profile/#{bob.id}")
      refute html =~ "Clinging"

      html = lv |> element("button", "Cling") |> render_click()
      assert html =~ "Clinging"
      assert Social.clinging?(alice.id, bob.id)

      html = lv |> element("button", "Clinging") |> render_click()
      refute html =~ "Clinging"
      refute Social.clinging?(alice.id, bob.id)
    end

    test "stats update live when someone clings from another session (PubSub)", %{
      conn: conn,
      alice: alice,
      bob: bob
    } do
      {:ok, lv, html} = live(log_in_user(conn, alice), ~p"/profile/#{bob.id}")
      assert html =~ "Clingers"

      {:ok, _} = Social.cling(alice.id, bob.id)

      # the LiveView subscribed to user:<bob.id>:stats in mount and should
      # re-render with the fresh count once the broadcast lands
      assert render(lv) =~ ">1<"
    end
  end

  describe "action row" do
    test "clicking an unbuilt action shows a coming-soon flash instead of a dead link", %{
      conn: conn,
      alice: alice
    } do
      {:ok, lv, _html} = live(log_in_user(conn, alice), ~p"/profile/#{alice.id}")

      html = lv |> element("button", "Start Gathering") |> render_click()
      assert html =~ "coming in a later phase"
    end
  end
end
