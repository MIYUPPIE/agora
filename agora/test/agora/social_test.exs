defmodule Agora.SocialTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures

  alias Agora.{Notifications, Social}

  describe "cling/2 and uncling/2" do
    test "clinging updates both sides' counts" do
      alice = user_fixture()
      bob = user_fixture()

      assert Social.clinger_count(bob.id) == 0
      assert Social.cling_count(alice.id) == 0
      refute Social.clinging?(alice.id, bob.id)

      assert {:ok, _cling} = Social.cling(alice.id, bob.id)

      assert Social.clinging?(alice.id, bob.id)
      assert Social.clinger_count(bob.id) == 1
      assert Social.cling_count(alice.id) == 1
      # unaffected: bob following alice is a separate edge
      assert Social.clinger_count(alice.id) == 0
    end

    test "unclinging removes the edge and updates counts" do
      alice = user_fixture()
      bob = user_fixture()
      {:ok, _} = Social.cling(alice.id, bob.id)

      assert :ok = Social.uncling(alice.id, bob.id)

      refute Social.clinging?(alice.id, bob.id)
      assert Social.clinger_count(bob.id) == 0
      assert Social.cling_count(alice.id) == 0
    end

    test "unclinging an edge that doesn't exist returns an error, not a crash" do
      alice = user_fixture()
      bob = user_fixture()

      assert {:error, :not_found} = Social.uncling(alice.id, bob.id)
    end

    test "clinging twice is rejected by the unique index" do
      alice = user_fixture()
      bob = user_fixture()
      {:ok, _} = Social.cling(alice.id, bob.id)

      assert {:error, changeset} = Social.cling(alice.id, bob.id)
      assert %{clinger_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "clinging to yourself is rejected" do
      alice = user_fixture()

      assert {:error, changeset} = Social.cling(alice.id, alice.id)
      assert %{clinged_id: ["can't cling to yourself"]} = errors_on(changeset)
    end

    test "cling broadcasts a stats_updated event for both users" do
      alice = user_fixture()
      bob = user_fixture()

      Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{alice.id}:stats")
      Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{bob.id}:stats")

      {:ok, _} = Social.cling(alice.id, bob.id)

      assert_receive {:stats_updated, alice_id} when alice_id == alice.id
      assert_receive {:stats_updated, bob_id} when bob_id == bob.id
    end

    test "uncling broadcasts a stats_updated event for both users" do
      alice = user_fixture()
      bob = user_fixture()
      {:ok, _} = Social.cling(alice.id, bob.id)

      Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{alice.id}:stats")
      Phoenix.PubSub.subscribe(Agora.PubSub, "user:#{bob.id}:stats")

      :ok = Social.uncling(alice.id, bob.id)

      assert_receive {:stats_updated, alice_id} when alice_id == alice.id
      assert_receive {:stats_updated, bob_id} when bob_id == bob.id
    end

    test "clinging notifies the person being clinged to" do
      alice = user_fixture()
      bob = user_fixture()

      {:ok, _} = Social.cling(alice.id, bob.id)

      assert [notification] = Notifications.list_for_user(bob.id)
      assert notification.type == :cling
      assert notification.actor_id == alice.id
    end
  end

  describe "list_clingers/1 and list_clings/1" do
    test "list_clingers returns the people who follow the user, newest first" do
      alice = user_fixture()
      bob = user_fixture()
      carol = user_fixture()
      {:ok, _} = Social.cling(bob.id, alice.id)
      # utc_datetime (second precision) + a non-monotonic UUID tie-break
      # means the ordering test needs a real second between inserts.
      Process.sleep(1100)
      {:ok, _} = Social.cling(carol.id, alice.id)

      assert Enum.map(Social.list_clingers(alice.id), & &1.id) == [carol.id, bob.id]
    end

    test "list_clings returns the people the user follows, newest first" do
      alice = user_fixture()
      bob = user_fixture()
      carol = user_fixture()
      {:ok, _} = Social.cling(alice.id, bob.id)
      Process.sleep(1100)
      {:ok, _} = Social.cling(alice.id, carol.id)

      assert Enum.map(Social.list_clings(alice.id), & &1.id) == [carol.id, bob.id]
    end

    test "each returned user has their profile preloaded" do
      alice = user_fixture()
      bob = user_fixture()
      {:ok, _} = Social.cling(alice.id, bob.id)

      assert [clinged] = Social.list_clings(alice.id)
      assert %Agora.Profiles.Profile{} = clinged.profile
    end
  end

  describe "clinging_set/2" do
    test "returns the subset of ids the viewer clings to" do
      viewer = user_fixture()
      clinged = user_fixture()
      not_clinged = user_fixture()
      {:ok, _} = Social.cling(viewer.id, clinged.id)

      assert Social.clinging_set(viewer.id, [clinged.id, not_clinged.id]) ==
               MapSet.new([clinged.id])
    end

    test "returns an empty set for an anonymous (nil) viewer" do
      clinged = user_fixture()
      assert Social.clinging_set(nil, [clinged.id]) == MapSet.new()
    end

    test "returns an empty set for an empty id list without querying" do
      viewer = user_fixture()
      assert Social.clinging_set(viewer.id, []) == MapSet.new()
    end
  end
end
