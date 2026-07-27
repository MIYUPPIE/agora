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

    test "registration already created the profile — get_or_create! is a pure fetch" do
      user = user_fixture()

      # A second manual insert attempt hits the unique index, proving a
      # profile row already exists from registration (Accounts.register_user),
      # not lazily from this call.
      assert {:error, changeset} =
               %Agora.Profiles.Profile{}
               |> Agora.Profiles.Profile.changeset(%{user_id: user.id, display_name: "racer"})
               |> Repo.insert()

      assert %{user_id: ["has already been taken"]} = errors_on(changeset)

      profile = Profiles.get_or_create!(user)
      refute profile.display_name == "racer"
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
    test "gathering_count is 0 until Phase 4 lands" do
      user = user_fixture()
      assert Profiles.gathering_count(user.id) == 0
    end
  end
end
