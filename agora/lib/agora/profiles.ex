defmodule Agora.Profiles do
  @moduledoc """
  Profile hub: the display identity (avatar, name, tagline, bio) layered
  on top of an Accounts.User.
  """

  alias Agora.Accounts.User
  alias Agora.Profiles.Profile
  alias Agora.Repo

  def get_by_user_id(user_id), do: Repo.get_by(Profile, user_id: user_id)

  @doc """
  A profile is created for every user at registration time (see
  `Agora.Accounts.register_user/1`), so this is a defensive fallback for
  any user that somehow doesn't have one yet — never the primary path.
  """
  def get_or_create!(%User{} = user) do
    case get_by_user_id(user.id) do
      nil -> create_default!(user)
      profile -> profile
    end
  end

  defp create_default!(user) do
    %Profile{}
    |> Profile.changeset(%{user_id: user.id, display_name: default_display_name(user)})
    |> Repo.insert(on_conflict: :nothing, conflict_target: :user_id)
    |> case do
      {:ok, %Profile{id: nil}} -> Repo.get_by!(Profile, user_id: user.id)
      {:ok, profile} -> profile
    end
  end

  @doc "The starting display_name for a brand-new profile: the email's local part."
  def default_display_name(%User{email: email}) do
    email |> String.split("@") |> hd()
  end

  def change_profile(%Profile{} = profile, attrs \\ %{}) do
    Profile.changeset(profile, attrs)
  end

  def update_profile(%Profile{} = profile, attrs) do
    profile
    |> Profile.changeset(attrs)
    |> Repo.update()
  end

  @doc "Gathering count. Stubbed at 0 until Phase 4 adds the gatherings table."
  def gathering_count(_user_id), do: 0
end
