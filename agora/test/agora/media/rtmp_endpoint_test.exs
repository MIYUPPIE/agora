defmodule Agora.Media.RTMPEndpointTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures

  alias Agora.Gatherings
  alias Agora.Media.RTMPEndpoint

  # handle_new_client/3 runs synchronously inside a real broadcast
  # connection's own Membrane.RTMPServer.ClientHandler GenServer, which is
  # itself linked to the shared RTMP accept-loop process (see
  # rtmp_endpoint.ex's moduledoc comment on reject_connection/0). These
  # tests reproduce that shape with a plain linked process standing in for
  # the ClientHandler, so a regression back to the old `:reject` atom (or
  # to an exit reason other than `:normal`) shows up here rather than only
  # in production logs.
  defp call_from_linked_client_process(app, stream_key) do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        receive do: (:go -> :ok)
        result = RTMPEndpoint.handle_new_client(self(), app, stream_key)
        send(parent, {:unexpectedly_returned, result})
      end)

    # spawn_monitor/1 doesn't inherit this test's Ecto sandbox connection —
    # the spawned process must be explicitly allowed before it's safe to
    # let it call Gatherings.get_by_stream_key/1, hence the :go handshake.
    Ecto.Adapters.SQL.Sandbox.allow(Agora.Repo, self(), pid)
    send(pid, :go)

    {pid, ref}
  end

  describe "handle_new_client/3 with an unknown or expired stream key" do
    test "ends only that client's own process with reason :normal, instead of returning :reject" do
      {_pid, ref} = call_from_linked_client_process("live", "no-such-key")

      # Before this fix, handle_new_client/3 returned the bare atom
      # :reject. membrane_rtmp_plugin's client_handler.ex then called
      # `:reject.handle_init/1` on that "handler module", crashing the
      # connection's GenServer with UndefinedFunctionError on every bad
      # stream key. The fix makes the client's own process exit cleanly
      # instead of returning a value at all — assert_receive below would
      # fail (the :unexpectedly_returned message would arrive) if that
      # regressed.
      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 2000
      refute_received {:unexpectedly_returned, _}
    end

    test "does not propagate through the link to kill the calling process" do
      # A GenServer.start_link/3'd ClientHandler is linked to
      # Membrane.RTMPServer.Listener's shared accept loop. Regressing
      # reject_connection/0 to `exit(:shutdown)` (or any non-:normal
      # reason) would take that whole accept loop — every other
      # broadcaster's connection — down with it. Proven directly: this
      # test process is linked to the spawned "client" process below, so
      # if the exit reason ever stops being :normal, this test process
      # dies too and the assertions after the receive never run.
      pid =
        spawn_link(fn ->
          receive do: (:go -> :ok)
          RTMPEndpoint.handle_new_client(self(), "live", "no-such-key")
        end)

      Ecto.Adapters.SQL.Sandbox.allow(Agora.Repo, self(), pid)
      Process.monitor(pid)
      send(pid, :go)
      assert_receive {:DOWN, _ref, :process, ^pid, :normal}, 2000

      # Still alive and able to do real work — the link did not propagate
      # a fatal exit signal up to this process.
      assert Process.alive?(self())
      user = user_fixture()
      assert {:ok, _gathering} = Gatherings.create_gathering(user.id, %{"title" => "Still here"})
    end

    test "also rejects a gathering that exists but isn't scheduled or live" do
      user = user_fixture()
      {:ok, gathering} = Gatherings.create_gathering(user.id, %{"title" => "Long over"})
      Gatherings.mark_live!(gathering.id)
      Gatherings.mark_ended!(gathering.id)

      {_pid, ref} = call_from_linked_client_process("live", gathering.stream_key)

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 2000
      refute_received {:unexpectedly_returned, _}
    end

    test "matches the real-world OBS misconfiguration: whole path as app, empty stream key" do
      # Reproduces the exact shape from the crash report this test guards
      # against: an encoder that was given the combined ingest URL as its
      # "Server" field (with "Stream Key" left blank) sends the full
      # "live/<key>" path as the RTMP `app` and an empty string as the
      # publish stream key.
      {_pid, ref} = call_from_linked_client_process("live/Dh6bJMTxHWyhCQ6FUQPD_6cccDAU8O66", "")

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 2000
      refute_received {:unexpectedly_returned, _}
    end
  end
end
