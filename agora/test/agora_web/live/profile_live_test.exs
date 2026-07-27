defmodule AgoraWeb.ProfileLiveTest do
  use AgoraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Agora.AccountsFixtures

  alias Agora.{Posts, Profiles, Social}

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

    test "renders all three post kinds as compact rows", %{conn: conn, alice: alice} do
      {:ok, _} = Posts.create_tiding(alice.id, %{"body" => "a tiding"})

      {:ok, _} =
        Posts.create_image_post(alice.id, %{"title" => "an image post"}, [
          %{url: "/uploads/a.jpg", byte_size: 1}
        ])

      {:ok, _} =
        Posts.create_audio_post(
          alice.id,
          %{"title" => "an audio post", "duration_ms" => 180_000},
          %{url: "/uploads/clip.m4a", byte_size: 1}
        )

      {:ok, _lv, html} = live(conn, ~p"/profile/#{alice.id}")

      assert html =~ "a tiding"
      assert html =~ "an image post"
      assert html =~ "1 Image"
      assert html =~ "an audio post"
      assert html =~ "Listen: 3:00"
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

    test "the action row only renders for the owner, not a visitor", %{
      conn: conn,
      alice: alice,
      bob: bob
    } do
      {:ok, _lv, html} = live(log_in_user(conn, alice), ~p"/profile/#{bob.id}")
      refute html =~ "Start Gathering"
      refute html =~ "Upload Image"
    end
  end

  describe "posting a tiding" do
    test "the owner can open the composer, post, and see it appear in their own list", %{
      conn: conn,
      alice: alice
    } do
      {:ok, lv, _html} = live(log_in_user(conn, alice), ~p"/profile/#{alice.id}")

      lv |> element("button", "Tidings") |> render_click()
      assert has_element?(lv, "textarea[name='tiding[body]']")

      html =
        lv
        |> form("form", tiding: %{body: "God moved mightily today"})
        |> render_submit()

      assert html =~ "God moved mightily today"
      assert html =~ ">1<"
      refute has_element?(lv, "textarea[name='tiding[body]']")
    end
  end

  describe "posting an image" do
    test "the owner can upload images and see the post appear", %{conn: conn, alice: alice} do
      {:ok, lv, _html} = live(log_in_user(conn, alice), ~p"/profile/#{alice.id}")

      lv |> element("button", "Upload Image") |> render_click()
      assert has_element?(lv, "#image-upload-form")

      image =
        file_input(lv, "#image-upload-form", :images, [
          %{
            name: "photo.jpg",
            content: tiny_jpeg(),
            type: "image/jpeg"
          }
        ])

      render_upload(image, "photo.jpg")

      html =
        lv
        |> form("#image-upload-form", %{"title" => "God moved Mightily in Ayingba"})
        |> render_submit()

      assert html =~ "God moved Mightily in Ayingba"
      assert html =~ "1 Image"
    end
  end

  defp tiny_jpeg do
    {:ok, image} = Image.new(20, 20, color: [200, 30, 30])
    {:ok, binary} = Image.write(image, :memory, suffix: ".jpg")
    binary
  end
end
