defmodule Agora.Workers.ArchiveGatheringTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures
  import Agora.MediaFixtures

  alias Agora.{Gatherings, Posts}
  alias Agora.Workers.ArchiveGathering

  test "builds the replay clip and creates an audio Post on the broadcaster's profile" do
    broadcaster = user_fixture()
    {:ok, gathering} = Gatherings.create_gathering(broadcaster.id, %{"title" => "Sunday service"})
    write_synthetic_segments!(gathering.id, duration_seconds: 2)

    assert :ok = perform_job(ArchiveGathering, %{"gathering_id" => gathering.id})

    assert [post] = Posts.list_for_user(broadcaster.id)
    assert post.kind == :audio
    assert post.title == "Sunday service"
    assert_in_delta post.duration_ms, 2000, 300
    assert [media] = post.media
    assert media.kind == :audio
    assert media.url == "/media/gatherings/#{gathering.id}/replay.m4a"
  end

  test "a gathering that never streamed audio archives to :ok with no post" do
    broadcaster = user_fixture()
    {:ok, gathering} = Gatherings.create_gathering(broadcaster.id, %{"title" => "Dead air"})

    assert :ok = perform_job(ArchiveGathering, %{"gathering_id" => gathering.id})
    assert Posts.list_for_user(broadcaster.id) == []
  end
end
