defmodule Agora.Posts.Reaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reactions" do
    belongs_to :user, Agora.Accounts.User
    belongs_to :post, Agora.Posts.Post

    field :kind, Ecto.Enum, values: [:heart, :torch]

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:user_id, :post_id, :kind])
    |> validate_required([:user_id, :post_id, :kind])
    |> unique_constraint([:user_id, :post_id, :kind])
  end
end
