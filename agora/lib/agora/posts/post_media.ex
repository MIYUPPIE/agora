defmodule Agora.Posts.PostMedia do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "post_media" do
    belongs_to :post, Agora.Posts.Post

    field :kind, Ecto.Enum, values: [:image, :audio]
    field :url, :string
    field :position, :integer, default: 0
    field :byte_size, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(post_media, attrs) do
    post_media
    |> cast(attrs, [:post_id, :kind, :url, :position, :byte_size])
    |> validate_required([:post_id, :kind, :url])
  end
end
