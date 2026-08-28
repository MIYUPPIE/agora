defmodule Agora.Media.Audio.WhisperCli do
  @moduledoc """
  One-shot `whisper-cli` invocation over a *complete* audio file —
  the high-accuracy archival pass `Agora.Workers.ArchiveGathering` runs
  once, after a Gathering ends, over the full replay clip
  `Agora.Media.build_clip/4` already built. Unlike
  `Agora.Media.Audio.WhisperClient` (the live path, HTTP against a
  long-running `whisper-server`), reloading a model once per Gathering
  is a non-issue for a background Oban job — so this uses whichever
  model `:whisper_final_model` points at (bigger/more accurate than the
  live model is the point; see `scripts/setup_whisper.sh`) without
  needing a second always-on server process for it.

  Two ffmpeg-verified details baked into `transcribe_file/1`:

    * The input needs converting to WAV first — confirmed hands-on,
      whisper.cpp's own audio loader (miniaudio) doesn't understand the
      AAC/m4a container `Media.build_clip/4` produces, unlike the raw
      WAV `Agora.Media.Audio.Wav` hands `whisper-server` on the live
      path (see that module's moduledoc for why *that* path skips
      ffmpeg). The exact sample rate/channels ffmpeg converts to here
      don't matter beyond "a WAV file" for the same reason.

    * `-oj` (JSON output) must be passed *without* `-nt`
      (`--no-timestamps`) — confirmed hands-on against a real build:
      with `-nt`, every segment's offsets collapse to one bogus
      `{0, 30000}` span covering the whole 30s model context window
      instead of the audio's real per-segment timestamps. `-nt` only
      suppresses stdout printing for every *other* output mode; for
      `-oj` it silently corrupts the one thing (`offsets`) this
      function exists to read.
  """

  require Logger

  alias Agora.Media.Audio.Hallucination

  @spec transcribe_file(Path.t()) ::
          {:ok, [%{text: String.t(), start_ms: integer(), end_ms: integer()}]}
          | {:error, term()}
  def transcribe_file(path) do
    cli = Application.get_env(:agora, :whisper_cli)
    model = Application.get_env(:agora, :whisper_final_model)

    cond do
      is_nil(cli) or not executable?(cli) ->
        {:error, :unavailable}

      is_nil(model) or not File.exists?(model) ->
        {:error, :unavailable}

      true ->
        do_transcribe(cli, model, path)
    end
  end

  defp do_transcribe(cli, model, path) do
    tmp = Path.join(System.tmp_dir!(), "agora_whisper_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    try do
      wav_path = Path.join(tmp, "audio.wav")
      out_basename = Path.join(tmp, "out")

      with :ok <- convert_to_wav(path, wav_path),
           {:ok, json} <- run_cli(cli, model, wav_path, out_basename) do
        {:ok, parse_segments(json)}
      end
    after
      File.rm_rf(tmp)
    end
  end

  defp convert_to_wav(in_path, out_path) do
    args = ~w(-y -i) ++ [in_path] ++ ~w(-ar 16000 -ac 1 -c:a pcm_s16le -vn) ++ [out_path]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_out, 0} -> :ok
      {out, code} -> {:error, {:ffmpeg_failed, code, out}}
    end
  end

  defp run_cli(cli, model, wav_path, out_basename) do
    threads = System.schedulers_online() |> min(8) |> Integer.to_string()

    args =
      ~w(-m) ++
        [model, "-f", wav_path, "-l", "auto", "-oj", "-of", out_basename, "-np", "-t", threads]

    case System.cmd(cli, args, stderr_to_stdout: true) do
      {_out, 0} ->
        (out_basename <> ".json")
        |> File.read()
        |> case do
          {:ok, contents} -> Jason.decode(contents)
          {:error, reason} -> {:error, {:missing_output, reason}}
        end

      {out, code} ->
        Logger.error("Agora.Media.Audio.WhisperCli: whisper-cli exited #{code}: #{out}")
        {:error, {:whisper_cli_failed, code}}
    end
  end

  defp parse_segments(%{"transcription" => segments}) when is_list(segments) do
    segments
    |> Enum.map(fn %{"offsets" => %{"from" => from, "to" => to}, "text" => text} ->
      %{text: String.trim(text), start_ms: from, end_ms: to}
    end)
    |> Enum.reject(&(&1.text == "" or Hallucination.hallucinated?(&1.text)))
  end

  defp parse_segments(_other), do: []

  defp executable?(path), do: File.exists?(path) || System.find_executable(path) != nil
end
