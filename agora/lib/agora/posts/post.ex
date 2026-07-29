defmodule Agora.Posts.Post do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "posts" do
    belongs_to :user, Agora.Accounts.User
    has_many :media, Agora.Posts.PostMedia, foreign_key: :post_id, preload_order: [asc: :position]
    has_many :reactions, Agora.Posts.Reaction
    has_many :comments, Agora.Posts.Comment

    field :kind, Ecto.Enum, values: [:audio, :image_set, :tiding]
    field :title, :string
    field :body, :string
    field :duration_ms, :integer
    field :waveform, {:array, :integer}

    timestamps(type: :utc_datetime)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:user_id, :kind, :title, :body, :duration_ms, :waveform])
    |> validate_required([:user_id, :kind])
    |> validate_length(:title, max: 200)
    |> validate_length(:body, max: 5_000)
    |> validate_by_kind()
  end

  defp validate_by_kind(changeset) do
    case get_field(changeset, :kind) do
      :tiding -> validate_required(changeset, [:body])
      _ -> changeset
    end
  end
end
