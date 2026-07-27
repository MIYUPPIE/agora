defmodule Agora.GatheringsTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures

  alias Agora.Gatherings

  describe "create_gathering/2" do
    test "creates a scheduled gathering with a unique stream key" do
      user = user_fixture()

      assert {:ok, gathering} =
               Gatherings.create_gathering(user.id, %{"title" => "Sunday service"})

      assert gathering.status == :scheduled
      assert gathering.title == "Sunday service"
      assert is_binary(gathering.stream_key)
      assert byte_size(gathering.stream_key) > 16
    end

    test "two gatherings never share a stream key" do
      user = user_fixture()
      {:ok, a} = Gatherings.create_gathering(user.id, %{"title" => "First"})
      {:ok, b} = Gatherings.create_gathering(user.id, %{"title" => "Second"})

      refute a.stream_key == b.stream_key
    end

    test "requires a title" do
      user = user_fixture()
      assert {:error, changeset} = Gatherings.create_gathering(user.id, %{"title" => ""})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "get_by_stream_key/1" do
    test "finds the gathering, nil when the key is unknown" do
      user = user_fixture()
      {:ok, gathering} = Gatherings.create_gathering(user.id, %{"title" => "Sunday service"})

      found = Gatherings.get_by_stream_key(gathering.stream_key)
      assert found.id == gathering.id
      assert Gatherings.get_by_stream_key("no-such-key") == nil
    end
  end

  describe "mark_live!/1 and mark_ended!/1" do
    test "flips status and stamps started_at / ended_at" do
      user = user_fixture()
      {:ok, gathering} = Gatherings.create_gathering(user.id, %{"title" => "Sunday service"})

      :ok = Gatherings.mark_live!(gathering.id)
      live = Gatherings.get!(gathering.id)
      assert live.status == :live
      assert live.started_at

      :ok = Gatherings.mark_ended!(gathering.id)
      ended = Gatherings.get!(gathering.id)
      assert ended.status == :ended
      assert ended.ended_at
    end
  end

  describe "ingest_url/1 and manifest_url/1" do
    test "builds the rtmp ingest url from the stream key" do
      user = user_fixture()
      {:ok, gathering} = Gatherings.create_gathering(user.id, %{"title" => "Sunday service"})

      assert Gatherings.ingest_url(gathering) =~ "rtmp://"
      assert Gatherings.ingest_url(gathering) =~ gathering.stream_key
    end

    test "builds the HLS manifest url from the gathering id" do
      user = user_fixture()
      {:ok, gathering} = Gatherings.create_gathering(user.id, %{"title" => "Sunday service"})

      assert Gatherings.manifest_url(gathering) == "/media/gatherings/#{gathering.id}/index.m3u8"
    end
  end

  describe "list_live/0" do
    test "returns only gatherings currently live" do
      user = user_fixture()
      {:ok, scheduled} = Gatherings.create_gathering(user.id, %{"title" => "Not yet"})
      {:ok, live} = Gatherings.create_gathering(user.id, %{"title" => "Live now"})
      {:ok, ended} = Gatherings.create_gathering(user.id, %{"title" => "Already done"})

      :ok = Gatherings.mark_live!(live.id)
      :ok = Gatherings.mark_live!(ended.id)
      :ok = Gatherings.mark_ended!(ended.id)

      ids = Gatherings.list_live() |> Enum.map(& &1.id)
      assert ids == [live.id]
      refute scheduled.id in ids
      refute ended.id in ids
    end
  end

  describe "count_for_user/1" do
    test "counts a user's own gatherings regardless of status" do
      alice = user_fixture()
      bob = user_fixture()
      {:ok, _} = Gatherings.create_gathering(alice.id, %{"title" => "One"})
      {:ok, ended} = Gatherings.create_gathering(alice.id, %{"title" => "Two"})
      :ok = Gatherings.mark_live!(ended.id)
      :ok = Gatherings.mark_ended!(ended.id)
      {:ok, _} = Gatherings.create_gathering(bob.id, %{"title" => "Not alice's"})

      assert Gatherings.count_for_user(alice.id) == 2
      assert Gatherings.count_for_user(bob.id) == 1
    end
  end
end
