defmodule Agora.NotificationsTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures

  alias Agora.{Gatherings, Notifications, Posts}

  describe "notify/4" do
    test "inserts a notification and broadcasts it on the recipient's topic" do
      actor = user_fixture()
      recipient = user_fixture()

      Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{recipient.id}:notifications")

      assert {:ok, notification} = Notifications.notify(recipient.id, actor.id, :cling)
      assert notification.recipient_id == recipient.id
      assert notification.actor_id == actor.id
      assert notification.type == :cling
      assert is_nil(notification.read_at)

      assert_receive {:notification_created, received}
      assert received.id == notification.id
    end

    test "is a no-op when the actor is the recipient" do
      user = user_fixture()

      assert {:ok, nil} = Notifications.notify(user.id, user.id, :cling)
      assert Notifications.list_for_user(user.id) == []
    end

    test "carries post_id, gathering_id, and reaction_kind through opts" do
      actor = user_fixture()
      recipient = user_fixture()
      {:ok, post} = Posts.create_tiding(recipient.id, %{"body" => "a post"})
      {:ok, gathering} = Gatherings.create_gathering(recipient.id, %{"title" => "a gathering"})

      assert {:ok, n1} =
               Notifications.notify(recipient.id, actor.id, :reaction,
                 post_id: post.id,
                 reaction_kind: :torch
               )

      assert n1.reaction_kind == :torch
      assert n1.post_id == post.id

      assert {:ok, n2} =
               Notifications.notify(recipient.id, actor.id, :gathering_live,
                 gathering_id: gathering.id
               )

      assert n2.gathering_id == gathering.id
    end
  end

  describe "list_for_user/1" do
    test "returns notifications newest first, with the actor's profile preloaded" do
      actor = user_fixture()
      recipient = user_fixture()

      {:ok, older} = Notifications.notify(recipient.id, actor.id, :cling)
      Process.sleep(1100)
      {:ok, newer} = Notifications.notify(recipient.id, actor.id, :cling)

      [first, second] = Notifications.list_for_user(recipient.id)
      assert first.id == newer.id
      assert second.id == older.id
      assert %Agora.Profiles.Profile{} = first.actor.profile
    end

    test "only returns notifications addressed to that user" do
      actor = user_fixture()
      recipient = user_fixture()
      someone_else = user_fixture()

      {:ok, _} = Notifications.notify(recipient.id, actor.id, :cling)

      assert Notifications.list_for_user(someone_else.id) == []
    end
  end

  describe "unread_count/1 and mark_all_read/1" do
    test "counts only unread notifications" do
      actor = user_fixture()
      recipient = user_fixture()

      assert Notifications.unread_count(recipient.id) == 0

      {:ok, _} = Notifications.notify(recipient.id, actor.id, :cling)
      {:ok, _} = Notifications.notify(recipient.id, actor.id, :cling)

      assert Notifications.unread_count(recipient.id) == 2
    end

    test "mark_all_read clears the unread count and returns the number updated" do
      actor = user_fixture()
      recipient = user_fixture()
      {:ok, _} = Notifications.notify(recipient.id, actor.id, :cling)
      {:ok, _} = Notifications.notify(recipient.id, actor.id, :cling)

      assert Notifications.mark_all_read(recipient.id) == 2
      assert Notifications.unread_count(recipient.id) == 0

      # idempotent — nothing left to mark
      assert Notifications.mark_all_read(recipient.id) == 0
    end

    test "mark_all_read does not touch another user's notifications" do
      actor = user_fixture()
      recipient = user_fixture()
      other = user_fixture()
      {:ok, _} = Notifications.notify(recipient.id, actor.id, :cling)
      {:ok, _} = Notifications.notify(other.id, actor.id, :cling)

      Notifications.mark_all_read(recipient.id)

      assert Notifications.unread_count(recipient.id) == 0
      assert Notifications.unread_count(other.id) == 1
    end
  end
end
