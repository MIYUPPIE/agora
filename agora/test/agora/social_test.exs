defmodule Agora.SocialTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures

  alias Agora.Social

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
  end
end
