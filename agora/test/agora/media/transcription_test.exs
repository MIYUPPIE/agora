defmodule Agora.Media.TranscriptionTest do
  use ExUnit.Case, async: true

  alias Agora.Media.Transcription

  describe "set_enabled/2" do
    test "returns :not_live when nothing is registered for the gathering" do
      assert Transcription.set_enabled(Ecto.UUID.generate(), false) == :not_live
    end

    test "pushes {:set_transcription_enabled, bool} to the registered pipeline process" do
      gathering_id = Ecto.UUID.generate()
      test_pid = self()

      {:ok, _pid} = FakePipeline.start_link(gathering_id: gathering_id, test_pid: test_pid)

      assert Transcription.set_enabled(gathering_id, false) == :ok
      assert_receive {:got_call, {:set_transcription_enabled, false}}

      assert Transcription.set_enabled(gathering_id, true) == :ok
      assert_receive {:got_call, {:set_transcription_enabled, true}}
    end
  end
end
