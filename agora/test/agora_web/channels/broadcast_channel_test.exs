defmodule AgoraWeb.BroadcastChannelTest do
  # async: false — a couple of tests mutate the global
  # :browser_broadcast_ffmpeg app env to simulate ffmpeg failing.
  use AgoraWeb.ChannelCase, async: false

  import Agora.AccountsFixtures

  alias Agora.Gatherings
  alias AgoraWeb.{BroadcastChannel, UserSocket}

  setup do
    user = user_fixture()
    other_user = user_fixture()
    {:ok, gathering} = Gatherings.create_gathering(user.id, %{"title" => "Sunday service"})

    %{user: user, other_user: other_user, gathering: gathering}
  end

  defp connect_as(user, gathering) do
    token = BroadcastChannel.broadcast_token(gathering, user)
    connect(UserSocket, %{"token" => token})
  end

  test "the owner can join and a bridge process starts", %{user: user, gathering: gathering} do
    {:ok, socket} = connect_as(user, gathering)
    {:ok, _reply, socket} = subscribe_and_join(socket, "broadcast:#{gathering.id}", %{})

    assert Process.alive?(socket.assigns.bridge)
  end

  test "a non-owner is rejected", %{other_user: other_user, gathering: gathering} do
    {:ok, socket} = connect_as(other_user, gathering)

    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(socket, "broadcast:#{gathering.id}", %{})
  end

  test "a token scoped to a different gathering is rejected", %{user: user, gathering: gathering} do
    {:ok, other_gathering} = Gatherings.create_gathering(user.id, %{"title" => "Other"})
    {:ok, socket} = connect_as(user, other_gathering)

    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(socket, "broadcast:#{gathering.id}", %{})
  end

  test "the socket refuses to connect without a valid token" do
    assert :error = connect(UserSocket, %{"token" => "garbage"})
    assert :error = connect(UserSocket, %{})
  end

  test "pushing a binary chunk doesn't crash the channel", %{user: user, gathering: gathering} do
    {:ok, socket} = connect_as(user, gathering)
    {:ok, _reply, socket} = subscribe_and_join(socket, "broadcast:#{gathering.id}", %{})

    push(socket, "chunk", {:binary, <<1, 2, 3>>})

    # If handle_in/3 had crashed, the channel process would be dead.
    assert Process.alive?(socket.channel_pid)
  end

  test "closing the channel stops its bridge process", %{user: user, gathering: gathering} do
    {:ok, socket} = connect_as(user, gathering)
    {:ok, _reply, socket} = subscribe_and_join(socket, "broadcast:#{gathering.id}", %{})
    bridge = socket.assigns.bridge

    # close/1 is documented as synchronous (blocks until the channel
    # process is confirmed down) but also documented to crash the test
    # process via their link unless we unlink first.
    Process.unlink(socket.channel_pid)
    close(socket)

    refute Process.alive?(bridge)
  end

  test "an unexpected ffmpeg exit pushes broadcast_error to the client", %{
    user: user,
    gathering: gathering
  } do
    Application.put_env(:agora, :browser_broadcast_ffmpeg, "false")
    on_exit(fn -> Application.put_env(:agora, :browser_broadcast_ffmpeg, "cat") end)

    {:ok, socket} = connect_as(user, gathering)
    {:ok, _reply, _socket} = subscribe_and_join(socket, "broadcast:#{gathering.id}", %{})

    assert_push "broadcast_error", %{status: status}
    assert status != 0
  end
end
