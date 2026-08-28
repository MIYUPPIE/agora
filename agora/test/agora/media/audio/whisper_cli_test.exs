defmodule Agora.Media.Audio.WhisperCliTest do
  use ExUnit.Case, async: true

  import Agora.MediaFixtures

  alias Agora.Media.Audio.WhisperCli

  describe "transcribe_file/1 — real model" do
    @describetag :whisper

    setup do
      cli = Application.get_env(:agora, :whisper_cli)
      model = Application.get_env(:agora, :whisper_final_model)

      if cli && File.exists?(cli) && model && File.exists?(model) do
        :ok
      else
        {:skip, "whisper.cpp not installed — run scripts/setup_whisper.sh"}
      end
    end

    test "transcribes real synthesized speech from an AAC/m4a file (the format Media.build_clip/4 produces) into timestamped segments" do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "agora_whisper_cli_test_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp)

      try do
        wav_path = Path.join(tmp, "speech.wav")
        m4a_path = Path.join(tmp, "speech.m4a")

        File.write!(
          wav_path,
          Agora.Media.Audio.Wav.encode(
            synth_speech_pcm!("The quick brown fox jumps over the lazy dog"),
            48_000,
            2
          )
        )

        {_out, 0} =
          System.cmd(
            "ffmpeg",
            ~w(-hide_banner -loglevel error -y -i) ++
              [wav_path] ++ ~w(-c:a aac -b:a 64k) ++ [m4a_path]
          )

        assert {:ok, [%{text: text, start_ms: start_ms, end_ms: end_ms} | _]} =
                 WhisperCli.transcribe_file(m4a_path)

        assert start_ms == 0
        assert end_ms > 0
        assert text =~ ~r/quick brown fox/i
      after
        File.rm_rf(tmp)
      end
    end
  end

  describe "transcribe_file/1 — unavailable configuration (no real binary needed)" do
    test "returns {:error, :unavailable} when whisper_cli isn't configured, without touching the real one" do
      original_cli = Application.get_env(:agora, :whisper_cli)
      Application.put_env(:agora, :whisper_cli, "/nonexistent/whisper-cli")

      try do
        assert WhisperCli.transcribe_file("/nonexistent/audio.m4a") == {:error, :unavailable}
      after
        Application.put_env(:agora, :whisper_cli, original_cli)
      end
    end

    test "returns {:error, :unavailable} when the model file doesn't exist" do
      original_model = Application.get_env(:agora, :whisper_final_model)
      Application.put_env(:agora, :whisper_final_model, "/nonexistent/model.bin")

      try do
        assert WhisperCli.transcribe_file("/nonexistent/audio.m4a") == {:error, :unavailable}
      after
        Application.put_env(:agora, :whisper_final_model, original_model)
      end
    end
  end
end
