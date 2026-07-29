defmodule Agora.Posts.Comment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "comments" do
    belongs_to :user, Agora.Accounts.User
    belongs_to :post, Agora.Posts.Post

    field :body, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:user_id, :post_id, :body])
    |> validate_required([:user_id, :post_id, :body])
    |> validate_length(:body, min: 1, max: 2_000)
  end
end
