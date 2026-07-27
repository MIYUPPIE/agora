defmodule Agora.Media.GatheringRegistry do
  @moduledoc "Registry mapping gathering_id -> pipeline pid."
  def child_spec(_), do: Registry.child_spec(keys: :unique, name: __MODULE__)
end
