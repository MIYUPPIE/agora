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
  end
end
