defmodule Agora.RecordingsTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures

  alias Agora.{Gatherings, Media, Recordings}

  setup do
    broadcaster = user_fixture()
    listener = user_fixture()
    {:ok, gathering} = Gatherings.create_gathering(broadcaster.id, %{"title" => "Test gathering"})
    %{listener: listener, gathering: gathering}
  end

  describe "start_recording/2" do
    test "snapshots the current head sequence as start_seq", %{listener: listener, gathering: g} do
      Media.insert_segment!(%{gathering_id: g.id, sequence: 0, filename: "a.m4s"})
      Media.insert_segment!(%{gathering_id: g.id, sequence: 1, filename: "b.m4s"})

      assert {:ok, recording} = Recordings.start_recording(listener.id, g.id)
      assert recording.start_seq == 1
      assert recording.status == :recording
    end
  end

  describe "record_from_start/2" do
    test "always starts at seq 0 regardless of the current head", %{
      listener: listener,
      gathering: g
    } do
      Media.insert_segment!(%{gathering_id: g.id, sequence: 0, filename: "a.m4s"})
      Media.insert_segment!(%{gathering_id: g.id, sequence: 5, filename: "f.m4s"})

      assert {:ok, recording} = Recordings.record_from_start(listener.id, g.id)
      assert recording.start_seq == 0
    end
  end

  describe "stop_recording/1" do
    test "snapshots end_seq, flips to processing, and enqueues a ClipBuilder job", %{
      listener: listener,
      gathering: g
    } do
      Media.insert_segment!(%{gathering_id: g.id, sequence: 0, filename: "a.m4s"})
      {:ok, recording} = Recordings.start_recording(listener.id, g.id)

      Media.insert_segment!(%{gathering_id: g.id, sequence: 1, filename: "b.m4s"})

      assert {:ok, stopped} = Recordings.stop_recording(recording)
      assert stopped.status == :processing
      assert stopped.end_seq == 1

      assert_enqueued(worker: Agora.Workers.ClipBuilder, args: %{recording_id: stopped.id})
    end
  end

  describe "active_for/2" do
    test "finds the in-progress recording for a user+gathering, nil once stopped", %{
      listener: listener,
      gathering: g
    } do
      refute Recordings.active_for(listener.id, g.id)

      {:ok, recording} = Recordings.start_recording(listener.id, g.id)
      active = Recordings.active_for(listener.id, g.id)
      assert active.id == recording.id

      {:ok, _stopped} = Recordings.stop_recording(recording)
      refute Recordings.active_for(listener.id, g.id)
    end
  end
end
