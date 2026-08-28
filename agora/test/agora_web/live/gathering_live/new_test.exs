defmodule AgoraWeb.GatheringLive.NewTest do
  use AgoraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Phoenix.ChannelTest
  import Agora.AccountsFixtures

  alias Agora.Gatherings
  alias Agora.Media.AudioEffects
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

  describe "the live audio effects panel" do
    test "renders once a Gathering exists, with default values", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

      html = lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      assert html =~ "Live Audio Studio"
      assert html =~ ~s(id="effects-form")
      assert html =~ "Noise Gate"
      assert html =~ "Equalizer"
      assert html =~ "Compressor"
      assert html =~ "Reverb"
      assert html =~ "Limiter"
      # Default input gain is 0.0dB — rendered via format_range_value/1.
      assert html =~ "0.00 dB"
    end

    test "moving a slider updates the rendered value and persists to the user's preset", %{
      conn: conn
    } do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      html =
        lv
        |> form("#effects-form", %{"input_gain_db" => "6.0"})
        |> render_change()

      assert html =~ "6.00 dB"
      assert AudioEffects.get_params(user.id).input_gain_db == 6.0
    end

    # Phoenix.LiveViewTest's form/3 derives checkbox "checked"-ness from
    # the rendered DOM, not from an override map (checked and value are
    # separate DOM concerns) — so exercising a checkbox flip needs
    # render_change/3 sending the raw payload directly, the same shape a
    # real browser would produce for the hidden-false/checkbox-true pair
    # rendered by `enabled_toggle/1`, rather than form/3 + render_change/1.
    test "checking a section's enabled toggle turns it on and persists the change", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      refute AudioEffects.get_params(user.id).reverb.enabled

      render_change(lv, "update_effect", %{"reverb" => %{"enabled" => "true"}})

      assert AudioEffects.get_params(user.id).reverb.enabled == true
    end

    test "unchecking a section's enabled toggle (submitting only the hidden false companion) turns it off",
         %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      assert AudioEffects.get_params(user.id).compressor.enabled

      render_change(lv, "update_effect", %{"compressor" => %{"enabled" => "false"}})

      refute AudioEffects.get_params(user.id).compressor.enabled
    end

    test "a slider change alongside other fields leaves sibling values untouched", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      html =
        lv
        |> form("#effects-form", %{"compressor" => %{"ratio" => "8.0"}})
        |> render_change()

      assert html =~ "8.00:1"
      params = AudioEffects.get_params(user.id)
      assert params.compressor.ratio == 8.0

      assert params.compressor.threshold_db ==
               Agora.Media.Audio.Params.default().compressor.threshold_db
    end

    test "out-of-range values submitted directly are clamped before being applied", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      lv
      |> form("#effects-form", %{"limiter" => %{"ceiling_db" => "50.0"}})
      |> render_change()

      assert AudioEffects.get_params(user.id).limiter.ceiling_db == 0.0
    end
  end

  describe "live chat on the broadcaster's own Studio page" do
    test "renders once a Gathering exists", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

      html = lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      assert html =~ "Live Chat"
      assert html =~ ~s(id="chat-messages")
    end

    test "a message the broadcaster sends is visible on their own page and clears the input", %{
      conn: conn
    } do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")
      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      lv
      |> form("form[phx-submit=send_chat]", %{"body" => "Welcome everyone!"})
      |> render_submit()

      html = render(lv)
      assert html =~ "Welcome everyone!"
      refute html =~ ~s(value="Welcome everyone!")
    end

    test "blank messages are not broadcast", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")
      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      lv |> form("form[phx-submit=send_chat]", %{"body" => "   "}) |> render_submit()
      refute has_element?(lv, "#chat-messages div")
    end

    # The whole point of this feature: the broadcaster stays on
    # /gatherings/new for the entire broadcast (see moduledoc) and
    # previously had no way to see the room's chat at all.
    test "a listener's message on the show page reaches the broadcaster's Studio page", %{
      conn: conn
    } do
      broadcaster = user_fixture()
      listener = user_fixture()

      {:ok, studio_lv, _html} = live(log_in_user(conn, broadcaster), ~p"/gatherings/new")

      studio_lv
      |> form("form", gathering: %{title: "Sunday service"})
      |> render_submit()

      gathering = hd(Agora.Repo.all(Agora.Gatherings.Gathering))
      Gatherings.mark_live!(gathering.id)

      {:ok, listener_lv, _html} =
        live(log_in_user(build_conn(), listener), ~p"/gatherings/#{gathering.id}")

      listener_lv
      |> form("form[phx-submit=send_chat]", %{"body" => "Can you hear us?"})
      |> render_submit()

      assert render(studio_lv) =~ "Can you hear us?"
    end
  end

  describe "live captions on the broadcaster's Studio page" do
    test "renders once a Gathering exists, captions on by default", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

      html = lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      assert html =~ "Captions will appear here"
      assert html =~ "Live captions"
      assert has_element?(lv, "input[phx-click='toggle_captions'][checked]")
    end

    test "toggling captions off pushes {:set_transcription_enabled, false} to the live pipeline",
         %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")
      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      gathering = hd(Agora.Repo.all(Agora.Gatherings.Gathering))
      {:ok, _pid} = FakePipeline.start_link(gathering_id: gathering.id, test_pid: self())

      html = render_click(lv, "toggle_captions")

      assert_receive {:got_call, {:set_transcription_enabled, false}}
      refute has_element?(lv, "input[phx-click='toggle_captions'][checked]")
      assert html =~ "Live captions"

      render_click(lv, "toggle_captions")
      assert_receive {:got_call, {:set_transcription_enabled, true}}
    end

    test "a live segment appears without a page reload", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")
      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      gathering = hd(Agora.Repo.all(Agora.Gatherings.Gathering))

      Agora.Transcripts.append_live_segment!(gathering.id, %{
        text: "Testing, testing, one two three.",
        start_ms: 0,
        end_ms: 1000
      })

      assert render(lv) =~ "Testing, testing, one two three."
    end
  end

  describe "the broadcaster's \"End Gathering\" button" do
    test "renders once a Gathering exists, with a confirmation prompt", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

      html = lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      assert html =~ "End Gathering"
      assert has_element?(lv, "button[phx-click='stop_broadcast'][data-confirm]")
    end

    test "clicking it ends an OBS-style Gathering (no browser bridge involved) and the banner updates live",
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

      assert render(lv) =~ "You&#39;re live"

      render_click(lv, "stop_broadcast")

      assert Gatherings.get!(gathering.id).status == :ended

      # stop_broadcast triggers the same {:gathering_ended, id} PubSub
      # message a natural disconnect would — the LiveView picks it up via
      # handle_info/2 (async relative to the click itself), same as every
      # other "ended" assertion in this file that renders again afterward.
      html = render(lv)
      refute html =~ "You&#39;re live"
      refute html =~ "End Gathering"
      assert_enqueued(worker: Agora.Workers.ArchiveGathering, args: %{gathering_id: gathering.id})
    end

    test "clicking it while a pipeline is registered delegates to it instead of ending the Gathering directly",
         %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")
      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      gathering = hd(Agora.Repo.all(Agora.Gatherings.Gathering))
      Gatherings.mark_live!(gathering.id)
      {:ok, _pid} = FakePipeline.start_link(gathering_id: gathering.id, test_pid: self())

      render_click(lv, "stop_broadcast")

      assert_receive {:got_call, :stop_broadcast}
      # FakePipeline is a bare echo stub, so it doesn't actually run the
      # real pipeline's own end_gathering_once/1 — status staying :live
      # here proves the click delegated rather than ending it twice over.
      assert Gatherings.get!(gathering.id).status == :live
    end
  end

  describe "the OBS ingest URL's copy control" do
    test "renders the copy hook wired to the exact ingest URL text", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

      html = lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()
      gathering = hd(Agora.Repo.all(Agora.Gatherings.Gathering))

      assert html =~ ~s(id="ingest-url-copy")
      assert html =~ ~s(phx-hook="CopyToClipboard")
      assert html =~ ~s(data-role="ingest-url")
      assert html =~ Gatherings.ingest_url(gathering)
    end

    # OBS/Streamlabs' "Custom..." RTMP service type takes a Server and a
    # Stream Key as two separate fields. A broadcaster who instead pasted
    # the combined ingest URL into "Server" alone (leaving "Stream Key"
    # blank) sends the whole "live/<key>" path as the RTMP app and an
    # empty stream key — which the server correctly rejects, but looks
    # like a broken connection with no obvious cause. These split fields
    # exist specifically to prevent that mistake.
    test "also renders the Server and Stream Key as separate copyable fields", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gatherings/new")

      html = lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()
      gathering = hd(Agora.Repo.all(Agora.Gatherings.Gathering))

      assert html =~ ~s(id="server-url-copy")
      assert html =~ ~s(id="stream-key-copy")
      assert html =~ Gatherings.server_url()
      assert html =~ gathering.stream_key

      # The Server field on its own must never carry the stream key —
      # that's exactly the value that, pasted alone, reproduces the bug.
      refute Gatherings.server_url() =~ gathering.stream_key
    end
  end

  describe "resuming an existing Studio session" do
    test "reopening the page (no id in the URL) drops the broadcaster back into their existing Gathering, not a blank form",
         %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/gatherings/new")
      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      assert [gathering] = Agora.Repo.all(Agora.Gatherings.Gathering)

      {:ok, _resumed_lv, html} = live(build_conn() |> log_in_user(user), ~p"/gatherings/new")

      assert html =~ Gatherings.ingest_url(gathering)
      assert html =~ "Waiting for your broadcast to start"
      refute html =~ "Initialize Gathering Studio"

      # Still exactly one Gathering — resuming must never mint a second
      # stream key alongside the one already handed to an encoder.
      assert Agora.Repo.aggregate(Agora.Gatherings.Gathering, :count) == 1
    end

    test "a resumed session reflects that the Gathering is already live", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/gatherings/new")
      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      gathering = hd(Agora.Repo.all(Agora.Gatherings.Gathering))
      Gatherings.mark_live!(gathering.id)

      {:ok, _lv, html} = live(build_conn() |> log_in_user(user), ~p"/gatherings/new")

      assert html =~ "You&#39;re live"
      refute html =~ "Waiting for your broadcast to start"
    end

    test "a resumed session still carries the transcript already gathered so far", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/gatherings/new")
      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      gathering = hd(Agora.Repo.all(Agora.Gatherings.Gathering))

      Agora.Transcripts.append_live_segment!(gathering.id, %{
        text: "Welcome everyone to the gathering",
        start_ms: 0,
        end_ms: 2000
      })

      {:ok, _lv, html} = live(build_conn() |> log_in_user(user), ~p"/gatherings/new")

      assert html =~ "Welcome everyone to the gathering"
    end

    test "a resumed session's browser-broadcast token still authorizes that Gathering", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/gatherings/new")
      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()
      gathering = hd(Agora.Repo.all(Agora.Gatherings.Gathering))

      {:ok, _lv, html} = live(build_conn() |> log_in_user(user), ~p"/gatherings/new")
      [_, token] = Regex.run(~r/data-token="([^"]+)"/, html)

      assert {:ok, socket} = Phoenix.ChannelTest.connect(UserSocket, %{"token" => token})

      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, BroadcastChannel, "broadcast:#{gathering.id}", %{})
    end

    test "once the Gathering has ended, reopening the page shows a fresh blank form again", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/gatherings/new")
      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()

      gathering = hd(Agora.Repo.all(Agora.Gatherings.Gathering))
      Gatherings.mark_live!(gathering.id)
      Gatherings.mark_ended!(gathering.id)

      {:ok, _lv, html} = live(build_conn() |> log_in_user(user), ~p"/gatherings/new")

      assert html =~ "Initialize Gathering Studio"
      refute html =~ Gatherings.ingest_url(gathering)
    end

    test "a different user reopening the page never resumes someone else's Gathering", %{
      conn: conn
    } do
      broadcaster = user_fixture()
      other_user = user_fixture()

      {:ok, lv, _html} = live(log_in_user(conn, broadcaster), ~p"/gatherings/new")
      lv |> form("form", gathering: %{title: "Sunday service"}) |> render_submit()
      gathering = hd(Agora.Repo.all(Agora.Gatherings.Gathering))

      {:ok, _lv, html} = live(build_conn() |> log_in_user(other_user), ~p"/gatherings/new")

      assert html =~ "Initialize Gathering Studio"
      refute html =~ Gatherings.ingest_url(gathering)
    end
  end

  defp extract_stream_key(html) do
    [_, key] = Regex.run(~r{rtmp://[^/]+/live/([^\s<]+)}, html)
    key
  end
end
