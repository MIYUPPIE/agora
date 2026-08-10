defmodule Agora.Workers.NotifyGatheringLiveTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures

  alias Agora.{Gatherings, Notifications, Social}
  alias Agora.Workers.NotifyGatheringLive

  test "notifies every Clinger of the broadcaster, and nobody else" do
    broadcaster = user_fixture(%{email: "jesse@example.com"})
    clinger = user_fixture()
    stranger = user_fixture()
    {:ok, _} = Social.cling(clinger.id, broadcaster.id)

    {:ok, gathering} = Gatherings.create_gathering(broadcaster.id, %{"title" => "Sunday service"})

    Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{clinger.id}:notifications")
    Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{stranger.id}:notifications")

    assert :ok = perform_job(NotifyGatheringLive, %{"gathering_id" => gathering.id})

    assert_receive {:gathering_live_notification, gathering_id, "jesse", "Sunday service"}
    assert gathering_id == gathering.id
    refute_receive {:gathering_live_notification, _, _, _}, 50
  end

  test "a broadcaster with no Clingers notifies nobody, without erroring" do
    broadcaster = user_fixture()
    {:ok, gathering} = Gatherings.create_gathering(broadcaster.id, %{"title" => "Quiet room"})

    assert :ok = perform_job(NotifyGatheringLive, %{"gathering_id" => gathering.id})
  end

  test "persists a notification for every Clinger, and nobody else" do
    broadcaster = user_fixture()
    clinger = user_fixture()
    stranger = user_fixture()
    {:ok, _} = Social.cling(clinger.id, broadcaster.id)

    {:ok, gathering} = Gatherings.create_gathering(broadcaster.id, %{"title" => "Sunday service"})

    assert :ok = perform_job(NotifyGatheringLive, %{"gathering_id" => gathering.id})

    assert [notification] = Notifications.list_for_user(clinger.id)
    assert notification.type == :gathering_live
    assert notification.actor_id == broadcaster.id
    assert notification.gathering_id == gathering.id
    assert Notifications.list_for_user(stranger.id) == []
  end
end
