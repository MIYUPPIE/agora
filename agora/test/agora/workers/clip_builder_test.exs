defmodule Agora.Workers.ClipBuilderTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures
  import Agora.MediaFixtures

  alias Agora.{Gatherings, Recordings}
  alias Agora.Workers.ClipBuilder

  test "turns a stopped recording into a ready download, broadcasting to the listener" do
    broadcaster = user_fixture()
    listener = user_fixture()
    {:ok, gathering} = Gatherings.create_gathering(broadcaster.id, %{"title" => "Sunday service"})
    write_synthetic_segments!(gathering.id, duration_seconds: 2)

    # record_from_start pins start_seq at 0 regardless of the current head,
    # so this recording spans every segment just written.
    {:ok, recording} = Recordings.record_from_start(listener.id, gathering.id)
    {:ok, recording} = Recordings.stop_recording(recording)

    Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{listener.id}:recordings")

    assert :ok = perform_job(ClipBuilder, %{"recording_id" => recording.id})

    ready = Recordings.get!(recording.id)
    assert ready.status == :ready
    # Exact match, not just a substring check — a prior bug duplicated the
    # "recordings/" prefix (Storage.put_local added its own on top of the
    # one already in this key), which a loose `=~` check wouldn't catch.
    assert ready.download_url == "/media/recordings/#{gathering.id}/#{recording.id}.m4a"
    assert ready.byte_size > 0

    assert_receive {:recording_ready, recording_id, url}
    assert recording_id == recording.id
    assert url == ready.download_url
  end

  test "a range with no segments fails the recording and notifies the listener" do
    broadcaster = user_fixture()
    listener = user_fixture()
    {:ok, gathering} = Gatherings.create_gathering(broadcaster.id, %{"title" => "Empty"})

    {:ok, recording} = Recordings.start_recording(listener.id, gathering.id)
    {:ok, recording} = Recordings.stop_recording(recording)

    Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{listener.id}:recordings")

    assert {:error, _reason} = perform_job(ClipBuilder, %{"recording_id" => recording.id})

    failed = Recordings.get!(recording.id)
    assert failed.status == :failed
    assert_receive {:recording_failed, recording_id}
    assert recording_id == recording.id
  end
end
