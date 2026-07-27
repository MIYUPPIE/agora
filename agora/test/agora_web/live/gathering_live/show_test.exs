defmodule AgoraWeb.GatheringLive.ShowTest do
  use AgoraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Agora.AccountsFixtures
  import Agora.MediaFixtures

  alias Agora.{Gatherings, Media, Recordings}

  describe "rendering" do
    test "a live gathering shows the player and listener count", %{conn: conn} do
      broadcaster = user_fixture()
      listener = user_fixture()

      {:ok, gathering} =
        Gatherings.create_gathering(broadcaster.id, %{"title" => "Sunday service"})

      :ok = Gatherings.mark_live!(gathering.id)

      {:ok, _lv, html} = live(log_in_user(conn, listener), ~p"/gatherings/#{gathering.id}")

      assert html =~ "Sunday service"
      assert html =~ "1 listening"
      assert html =~ "phx-hook=\"HlsPlayer\""
      assert html =~ Gatherings.manifest_url(gathering)
    end

    test "a scheduled (not-yet-live) gathering shows a waiting message, no player", %{conn: conn} do
      broadcaster = user_fixture()
      listener = user_fixture()
      {:ok, gathering} = Gatherings.create_gathering(broadcaster.id, %{"title" => "Later"})

      {:ok, _lv, html} = live(log_in_user(conn, listener), ~p"/gatherings/#{gathering.id}")

      assert html =~ "live right now"
      refute html =~ "HlsPlayer"
    end

    test "redirects anonymous visitors to log in", %{conn: _conn} do
      broadcaster = user_fixture()

      {:ok, gathering} =
        Gatherings.create_gathering(broadcaster.id, %{"title" => "Sunday service"})

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(build_conn(), ~p"/gatherings/#{gathering.id}")
    end
  end

  describe "presence" do
    test "listener count reflects everyone currently on the page", %{conn: conn} do
      broadcaster = user_fixture()
      alice = user_fixture()
      bob = user_fixture()

      {:ok, gathering} =
        Gatherings.create_gathering(broadcaster.id, %{"title" => "Sunday service"})

      :ok = Gatherings.mark_live!(gathering.id)

      {:ok, alice_lv, html} = live(log_in_user(conn, alice), ~p"/gatherings/#{gathering.id}")
      assert html =~ "1 listening"

      {:ok, _bob_lv, _html} =
        live(log_in_user(build_conn(), bob), ~p"/gatherings/#{gathering.id}")

      # presence_diff is async across processes; give it a moment to land.
      Process.sleep(50)
      assert render(alice_lv) =~ "2 listening"
    end
  end

  describe "recording" do
    test "record -> stop enqueues a ClipBuilder job, and recording_ready updates the download link",
         %{
           conn: conn
         } do
      broadcaster = user_fixture()
      listener = user_fixture()

      {:ok, gathering} =
        Gatherings.create_gathering(broadcaster.id, %{"title" => "Sunday service"})

      :ok = Gatherings.mark_live!(gathering.id)
      write_synthetic_segments!(gathering.id, duration_seconds: 1)

      {:ok, lv, _html} = live(log_in_user(conn, listener), ~p"/gatherings/#{gathering.id}")

      html = lv |> element("button", "Record from now") |> render_click()
      assert html =~ "Stop"

      lv |> element("button", "Stop") |> render_click()

      # stop_recording flips status to :processing — the recording stays
      # assigned (still shows "Stop & download") until the async ClipBuilder
      # job finishes and pushes recording_ready; it's no longer "active"
      # (i.e. re-clickable as a fresh recording) in the meantime.
      refute Recordings.active_for(listener.id, gathering.id)

      [recording] = Agora.Repo.all(Agora.Recordings.Recording)
      assert recording.status == :processing
      assert_enqueued(worker: Agora.Workers.ClipBuilder, args: %{recording_id: recording.id})

      Phoenix.PubSub.broadcast(
        Agora.PubSub,
        "user:#{listener.id}:recordings",
        {:recording_ready, recording.id, "/media/recordings/#{gathering.id}/#{recording.id}.m4a"}
      )

      assert render(lv) =~ "Download your recording"
    end

    test "record from the beginning starts at seq 0 even if segments already exist", %{conn: conn} do
      broadcaster = user_fixture()
      listener = user_fixture()

      {:ok, gathering} =
        Gatherings.create_gathering(broadcaster.id, %{"title" => "Sunday service"})

      :ok = Gatherings.mark_live!(gathering.id)
      write_synthetic_segments!(gathering.id, duration_seconds: 2)

      {:ok, lv, _html} = live(log_in_user(conn, listener), ~p"/gatherings/#{gathering.id}")
      lv |> element("button", "Record from the beginning") |> render_click()

      recording = Recordings.active_for(listener.id, gathering.id)
      assert recording.start_seq == 0
      assert Media.current_sequence(gathering.id) > 0
    end

    test "the recording indicator ticks up live as new segments land", %{conn: conn} do
      broadcaster = user_fixture()
      listener = user_fixture()

      {:ok, gathering} =
        Gatherings.create_gathering(broadcaster.id, %{"title" => "Sunday service"})

      :ok = Gatherings.mark_live!(gathering.id)

      {:ok, lv, _html} = live(log_in_user(conn, listener), ~p"/gatherings/#{gathering.id}")
      lv |> element("button", "Record from now") |> render_click()

      assert render(lv) =~ "Recording — 0s"

      send(lv.pid, {:segment, 1})
      assert render(lv) =~ "Recording — 4s"

      send(lv.pid, {:segment, 2})
      assert render(lv) =~ "Recording — 8s"
    end
  end

  describe "in-Gathering chat" do
    test "a sent message is visible to every session in the Gathering, and clears the input", %{
      conn: conn
    } do
      broadcaster = user_fixture()
      alice = user_fixture(%{email: "alice@example.com"})
      bob = user_fixture()

      {:ok, gathering} =
        Gatherings.create_gathering(broadcaster.id, %{"title" => "Sunday service"})

      :ok = Gatherings.mark_live!(gathering.id)

      {:ok, alice_lv, _html} = live(log_in_user(conn, alice), ~p"/gatherings/#{gathering.id}")
      {:ok, bob_lv, _html} = live(log_in_user(build_conn(), bob), ~p"/gatherings/#{gathering.id}")

      alice_lv
      |> form("form[phx-submit=send_chat]", %{"body" => "Amen!"})
      |> render_submit()

      # render_submit returns as soon as handle_event completes, which is
      # before alice's own PubSub broadcast round-trips back to her own
      # process as a handle_info — re-render to observe the settled state.
      html = render(alice_lv)
      assert html =~ "alice"
      assert html =~ "Amen!"
      # the input clears after sending, not left holding the sent text
      refute html =~ ~s(value="Amen!")

      assert render(bob_lv) =~ "Amen!"
    end

    test "blank messages are not broadcast", %{conn: conn} do
      broadcaster = user_fixture()
      listener = user_fixture()

      {:ok, gathering} =
        Gatherings.create_gathering(broadcaster.id, %{"title" => "Sunday service"})

      :ok = Gatherings.mark_live!(gathering.id)

      {:ok, lv, _html} = live(log_in_user(conn, listener), ~p"/gatherings/#{gathering.id}")

      lv |> form("form[phx-submit=send_chat]", %{"body" => "   "}) |> render_submit()
      refute has_element?(lv, "#chat-messages div")
    end
  end
end
