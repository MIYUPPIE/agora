defmodule Agora.Social.Cling do
  use Ecto.Schema
  import Ecto.Changeset

  schema "clings" do
    belongs_to :clinger, Agora.Accounts.User
    belongs_to :clinged, Agora.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(cling, attrs) do
    cling
    |> cast(attrs, [:clinger_id, :clinged_id])
    |> validate_required([:clinger_id, :clinged_id])
    |> validate_not_self()
    |> unique_constraint([:clinger_id, :clinged_id])
    |> check_constraint(:clinger_id, name: :clinger_is_not_clinged)
  end

  defp validate_not_self(changeset) do
    if get_field(changeset, :clinger_id) == get_field(changeset, :clinged_id) do
      add_error(changeset, :clinged_id, "can't cling to yourself")
    else
      changeset
    end
  end
end
