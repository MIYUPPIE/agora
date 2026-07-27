defmodule AgoraWeb.UserSocket do
  @moduledoc """
  The only channel mounted here is "broadcast:*" — see
  AgoraWeb.BroadcastChannel and Agora.Media.BrowserBroadcastBridge for
  the browser-native "go live with no OBS" feature this exists for.
  """

  use Phoenix.Socket

  channel "broadcast:*", AgoraWeb.BroadcastChannel

  @max_token_age :timer.hours(1)

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Phoenix.Token.verify(AgoraWeb.Endpoint, "browser_broadcast", token,
           max_age: @max_token_age
         ) do
      {:ok, claims} -> {:ok, assign(socket, :claims, claims)}
      {:error, _reason} -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(_socket), do: nil
end
