defmodule Agora.Media.Audio.WhisperServerTest do
  use ExUnit.Case, async: true

  alias Agora.Media.Audio.WhisperServer

  describe "init/1 — self-disabling when not configured (no real binary needed)" do
    test "stays unavailable, without attempting to boot, when :whisper_server_bin is unset" do
      with_env([whisper_server_bin: nil, whisper_live_model: "/some/model.bin"], fn ->
        assert {:ok, state} = WhisperServer.init([])
        refute state.available
        assert state.port == nil
      end)
    end

    test "stays unavailable when the configured binary doesn't exist on disk" do
      with_env(
        [
          whisper_server_bin: "/nonexistent/whisper-server",
          whisper_live_model: "/some/model.bin"
        ],
        fn ->
          assert {:ok, state} = WhisperServer.init([])
          refute state.available
        end
      )
    end

    test "stays unavailable when the configured model doesn't exist on disk" do
      with_env(
        [
          whisper_server_bin: System.find_executable("cat"),
          whisper_live_model: "/nonexistent/model.bin"
        ],
        fn ->
          assert {:ok, state} = WhisperServer.init([])
          refute state.available
        end
      )
    end
  end

  defp with_env(kv, fun) do
    originals = Enum.map(kv, fn {k, _} -> {k, Application.get_env(:agora, k)} end)
    Enum.each(kv, fn {k, v} -> Application.put_env(:agora, k, v) end)

    try do
      fun.()
    after
      Enum.each(originals, fn {k, v} -> Application.put_env(:agora, k, v) end)
    end
  end
end
