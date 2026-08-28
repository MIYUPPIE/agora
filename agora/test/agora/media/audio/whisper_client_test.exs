defmodule Agora.Media.Audio.WhisperClientTest do
  # async: false — Agora.Media.Audio.WhisperServer registers itself under
  # a fixed global name (see its moduledoc: one shared server, reused by
  # every live Gathering), so only one test process may own it at a time.
  use ExUnit.Case, async: false

  alias Agora.Media.Audio.{WhisperClient, WhisperServer}

  @moduletag :whisper
  @boot_timeout_ms 20_000

  setup_all do
    bin = Application.get_env(:agora, :whisper_server_bin)
    model = Application.get_env(:agora, :whisper_live_model)

    if bin && File.exists?(bin) && model && File.exists?(model) do
      start_supervised!(WhisperServer)
      wait_until_available!()
      :ok
    else
      {:skip, "whisper.cpp not installed — run scripts/setup_whisper.sh"}
    end
  end

  describe "transcribe/1 — real whisper-server round trip" do
    test "transcribes real synthesized speech correctly (48kHz stereo PCM, no ffmpeg resample step)" do
      pcm = Agora.MediaFixtures.synth_speech_pcm!("Pack my box with five dozen liquor jugs")

      assert {:ok, text} = WhisperClient.transcribe(pcm)
      # Whisper commonly renders spoken number words as numerals ("5"
      # rather than "five") regardless of how the source audio actually
      # pronounces them — a known, expected quirk of its decoding, not a
      # recognition error — so accept either form here.
      assert text =~ ~r/(five|5) dozen/i
    end

    test "true digital silence is filtered out rather than returning a hallucinated transcript" do
      pcm = <<0::size(48_000 * 2 * 2 * 8)>>
      assert WhisperClient.transcribe(pcm) == {:ok, nil}
    end
  end

  defp wait_until_available!(deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + @boot_timeout_ms

    cond do
      WhisperServer.available?() ->
        :ok

      System.monotonic_time(:millisecond) < deadline ->
        Process.sleep(200)
        wait_until_available!(deadline)

      true ->
        flunk("whisper-server did not become available within #{@boot_timeout_ms}ms")
    end
  end
end
