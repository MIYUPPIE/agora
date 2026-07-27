defmodule AgoraWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests, backed by a `Phoenix.PubSub` and the
  Ecto SQL sandbox.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import AgoraWeb.ChannelCase

      @endpoint AgoraWeb.Endpoint
    end
  end

  setup tags do
    Agora.DataCase.setup_sandbox(tags)
    :ok
  end
end
