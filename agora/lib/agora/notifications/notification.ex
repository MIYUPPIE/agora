defmodule Agora.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "notifications" do
    belongs_to :recipient, Agora.Accounts.User
    belongs_to :actor, Agora.Accounts.User
    belongs_to :post, Agora.Posts.Post
    belongs_to :gathering, Agora.Gatherings.Gathering

    field :type, Ecto.Enum, values: [:cling, :comment, :reaction, :gathering_live]
    field :reaction_kind, Ecto.Enum, values: [:heart, :torch]
    field :read_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :recipient_id,
      :actor_id,
      :post_id,
      :gathering_id,
      :type,
      :reaction_kind,
      :read_at
    ])
    |> validate_required([:recipient_id, :type])
  end
end
