defmodule AgoraWeb.ClingsLiveTest do
  use AgoraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Agora.AccountsFixtures

  alias Agora.{Profiles, Social}

  setup do
    %{alice: user_fixture(), bob: user_fixture(), carol: user_fixture()}
  end

  describe "the clingers tab" do
    test "lists everyone who follows the profile owner", %{conn: conn, alice: alice, bob: bob} do
      {:ok, _} = Social.cling(bob.id, alice.id)

      {:ok, _lv, html} = live(conn, ~p"/profile/#{alice.id}/clingers")

      bob_profile = Profiles.get_or_create!(bob)
      assert html =~ bob_profile.display_name
      assert html =~ "1 Clingers"
    end

    test "shows an empty state when nobody clings to the owner", %{conn: conn, alice: alice} do
      {:ok, _lv, html} = live(conn, ~p"/profile/#{alice.id}/clingers")
      assert html =~ "No Clingers yet."
    end
  end

  describe "the clings tab" do
    test "lists everyone the profile owner follows", %{conn: conn, alice: alice, bob: bob} do
      {:ok, _} = Social.cling(alice.id, bob.id)

      {:ok, _lv, html} = live(conn, ~p"/profile/#{alice.id}/clings")

      bob_profile = Profiles.get_or_create!(bob)
      assert html =~ bob_profile.display_name
      assert html =~ "1 Clings"
    end

    test "switching tabs patches to the other list without a full remount", %{
      conn: conn,
      alice: alice,
      bob: bob
    } do
      {:ok, _} = Social.cling(alice.id, bob.id)
      {:ok, lv, _html} = live(conn, ~p"/profile/#{alice.id}/clingers")

      html = lv |> element("a", "1 Clings") |> render_click()
      bob_profile = Profiles.get_or_create!(bob)
      assert html =~ bob_profile.display_name
    end
  end

  describe "clinging from the list" do
    test "an anonymous visitor clicking Cling is redirected to log in", %{
      conn: conn,
      alice: alice,
      bob: bob
    } do
      {:ok, _} = Social.cling(bob.id, alice.id)
      {:ok, lv, _html} = live(conn, ~p"/profile/#{alice.id}/clingers")

      {:error, {:live_redirect, %{to: to}}} =
        lv |> element("button", "Cling") |> render_click()

      assert to == ~p"/users/log-in"
    end

    test "a signed-in visitor can cling and uncling straight from the list", %{
      conn: conn,
      alice: alice,
      bob: bob,
      carol: carol
    } do
      {:ok, _} = Social.cling(bob.id, alice.id)
      {:ok, lv, html} = live(log_in_user(conn, carol), ~p"/profile/#{alice.id}/clingers")
      refute html =~ "Clinging"

      html = lv |> element("button", "Cling") |> render_click()
      assert html =~ "Clinging"
      assert Social.clinging?(carol.id, bob.id)

      html = lv |> element("button", "Clinging") |> render_click()
      refute html =~ "Clinging"
      refute Social.clinging?(carol.id, bob.id)
    end

    test "the owner does not see a Cling button next to their own row", %{
      conn: conn,
      alice: alice,
      bob: bob
    } do
      {:ok, _} = Social.cling(bob.id, alice.id)
      {:ok, _lv, html} = live(log_in_user(conn, bob), ~p"/profile/#{alice.id}/clingers")

      refute html =~ ">Cling<"
    end
  end

  test "unknown profile id renders 404", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/profile/#{Ecto.UUID.generate()}/clingers")
    end
  end
end
