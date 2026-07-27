defmodule AgoraWeb.PostLive.ShowTest do
  use AgoraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Agora.AccountsFixtures

  alias Agora.Posts

  describe "rendering" do
    test "tiding shows its body as the headline and text", %{conn: conn} do
      author = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "The Gospel is taking over"})

      {:ok, _lv, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "The Gospel is taking over"
      assert html =~ ">0<"
    end

    test "image_set renders every image", %{conn: conn} do
      author = user_fixture()

      {:ok, post} =
        Posts.create_image_post(author.id, %{"title" => "3 Images"}, [
          %{url: "/uploads/a.jpg", byte_size: 1},
          %{url: "/uploads/b.jpg", byte_size: 1}
        ])

      {:ok, _lv, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "3 Images"
      assert html =~ "/uploads/a.jpg"
      assert html =~ "/uploads/b.jpg"
    end

    test "audio without a waveform falls back to a plain player", %{conn: conn} do
      author = user_fixture()

      {:ok, post} =
        Posts.create_audio_post(
          author.id,
          %{"title" => "Sounds of mystery", "duration_ms" => 180_000},
          %{url: "/uploads/clip.m4a", byte_size: 10}
        )

      {:ok, _lv, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "Sounds of mystery"
      assert html =~ "<audio"
      assert html =~ "/uploads/clip.m4a"
      refute html =~ "WaveformPlayer"
    end

    test "audio with a waveform renders the canvas hook instead of a plain player", %{conn: conn} do
      author = user_fixture()

      {:ok, post} =
        Posts.create_audio_post(
          author.id,
          %{
            "title" => "Sounds of mystery",
            "duration_ms" => 180_000,
            "waveform" => [1, 4, 2, 6, 3]
          },
          %{url: "/uploads/clip.m4a", byte_size: 10}
        )

      {:ok, _lv, html} = live(conn, ~p"/posts/#{post.id}")

      assert html =~ "<canvas"
      assert html =~ "data-src=\"/uploads/clip.m4a\""
      refute html =~ "<audio"
    end

    test "anonymous visitors can view a post without an account", %{conn: conn} do
      author = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "public post"})

      assert {:ok, _lv, html} = live(conn, ~p"/posts/#{post.id}")
      assert html =~ "public post"
    end

    test "unknown post id renders 404", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/posts/999999999") end
    end
  end

  describe "reactions" do
    test "an anonymous visitor clicking react is redirected to log in", %{conn: conn} do
      author = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "react to me"})
      {:ok, lv, _html} = live(conn, ~p"/posts/#{post.id}")

      {:error, {:live_redirect, %{to: to}}} =
        lv |> element("button[phx-value-kind=heart]") |> render_click()

      assert to == ~p"/users/log-in"
    end

    test "a signed-in visitor can heart and un-heart, count and highlight flipping live", %{
      conn: conn
    } do
      author = user_fixture()
      reactor = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "react to me"})

      {:ok, lv, _html} = live(log_in_user(conn, reactor), ~p"/posts/#{post.id}")

      html = lv |> element("button[phx-value-kind=heart]") |> render_click()
      assert html =~ ">1<"
      assert Posts.reacted?(reactor.id, post.id, :heart)

      html = lv |> element("button[phx-value-kind=heart]") |> render_click()
      assert html =~ ">0<"
      refute Posts.reacted?(reactor.id, post.id, :heart)
    end

    test "reactions from another session update this view live", %{conn: conn} do
      author = user_fixture()
      reactor = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "react to me"})

      {:ok, lv, _html} = live(conn, ~p"/posts/#{post.id}")

      :ok = Posts.toggle_reaction(reactor.id, post.id, :torch)

      assert render(lv) =~ ">1<"
    end

    test "heart and torch counts are independent", %{conn: conn} do
      author = user_fixture()
      reactor = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "react to me"})

      {:ok, lv, _html} = live(log_in_user(conn, reactor), ~p"/posts/#{post.id}")

      lv |> element("button[phx-value-kind=heart]") |> render_click()
      html = lv |> element("button[phx-value-kind=torch]") |> render_click()

      assert Posts.reaction_counts(post.id) == %{heart: 1, torch: 1}
      assert html =~ ">1<"
    end
  end
end
