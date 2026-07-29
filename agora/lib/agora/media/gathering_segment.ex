defmodule Agora.Media.GatheringSegment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "gathering_segments" do
    belongs_to :gathering, Agora.Gatherings.Gathering
    field :sequence, :integer
    field :filename, :string
    field :byte_size, :integer
    field :duration_ms, :integer
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(segment, attrs) do
    segment
    |> cast(attrs, [:gathering_id, :sequence, :filename, :byte_size, :duration_ms])
    |> validate_required([:gathering_id, :sequence, :filename])
    |> unique_constraint([:gathering_id, :sequence])
  end
end
