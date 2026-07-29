defmodule Agora.Gatherings.Gathering do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "gatherings" do
    belongs_to :user, Agora.Accounts.User

    field :title, :string
    field :status, Ecto.Enum, values: [:scheduled, :live, :ended], default: :scheduled
    field :stream_key, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(gathering, attrs) do
    gathering
    |> cast(attrs, [:user_id, :title, :stream_key])
    |> validate_required([:user_id, :title, :stream_key])
    |> validate_length(:title, min: 1, max: 200)
    |> unique_constraint(:stream_key)
  end
end
