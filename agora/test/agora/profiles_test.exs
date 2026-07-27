defmodule Agora.ProfilesTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures

  alias Agora.Profiles

  describe "get_or_create!/1" do
    test "creates a default profile derived from the user's email" do
      user = user_fixture(%{email: "jesse.falodun@example.com"})

      profile = Profiles.get_or_create!(user)

      assert profile.user_id == user.id
      assert profile.display_name == "jesse.falodun"
      assert profile.tagline == nil
    end

    test "returns the existing profile on subsequent calls instead of duplicating" do
      user = user_fixture()

      first = Profiles.get_or_create!(user)
      second = Profiles.get_or_create!(user)

      assert first.id == second.id
    end

    test "is safe under a concurrent-create race (unique index wins, we re-fetch)" do
      user = user_fixture()

      # Simulate two requests racing to create the same user's profile: the
      # second insert hits the unique index and we fall back to a fetch.
      {:ok, _} =
        %Agora.Profiles.Profile{}
        |> Agora.Profiles.Profile.changeset(%{user_id: user.id, display_name: "racer"})
        |> Repo.insert()

      profile = Profiles.get_or_create!(user)
      assert profile.display_name == "racer"
    end
  end

  describe "update_profile/2" do
    test "updates display_name, tagline, bio" do
      user = user_fixture()
      profile = Profiles.get_or_create!(user)

      assert {:ok, updated} =
               Profiles.update_profile(profile, %{
                 display_name: "Jesse Falodun",
                 tagline: "Singer, Song Writer, Preacher etc",
                 bio: "Gospel on the radio."
               })

      assert updated.display_name == "Jesse Falodun"
      assert updated.tagline == "Singer, Song Writer, Preacher etc"
    end

    test "rejects a blank display_name" do
      profile = Profiles.get_or_create!(user_fixture())

      assert {:error, changeset} = Profiles.update_profile(profile, %{display_name: ""})
      assert %{display_name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "stubs pending later phases" do
    test "post_count and gathering_count are 0 until Phases 3/4 land" do
      user = user_fixture()
      assert Profiles.post_count(user.id) == 0
      assert Profiles.gathering_count(user.id) == 0
    end
  end
end
