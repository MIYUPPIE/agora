defmodule Agora.Recordings.Recording do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "recordings" do
    belongs_to :user, Agora.Accounts.User
    belongs_to :gathering, Agora.Gatherings.Gathering

    field :start_seq, :integer
    field :end_seq, :integer
    field :status, Ecto.Enum, values: [:recording, :processing, :ready, :failed]
    field :download_url, :string
    field :byte_size, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(recording, attrs) do
    recording
    |> cast(attrs, [
      :user_id,
      :gathering_id,
      :start_seq,
      :end_seq,
      :status,
      :download_url,
      :byte_size
    ])
    |> validate_required([:user_id, :gathering_id, :start_seq, :status])
  end
end
