defmodule Agora.Profiles.Profile do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "profiles" do
    belongs_to :user, Agora.Accounts.User

    field :display_name, :string
    field :tagline, :string
    field :avatar_url, :string
    field :cover_url, :string
    field :bio, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:user_id, :display_name, :tagline, :avatar_url, :cover_url, :bio])
    |> validate_required([:user_id, :display_name])
    |> validate_length(:display_name, min: 1, max: 80)
    |> validate_length(:tagline, max: 160)
    |> validate_length(:bio, max: 2000)
    |> unique_constraint(:user_id)
  end
end
