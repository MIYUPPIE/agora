defmodule Agora.Media.Audio.WhisperClient do
  @moduledoc """
  HTTP client for the shared `Agora.Media.Audio.WhisperServer` — turns
  one utterance's raw PCM (from `Agora.Media.Audio.UtteranceBuffer`)
  into text, via a `multipart/form-data` POST to whisper-server's
  `/inference` endpoint (confirmed against a real running instance: no
  ffmpeg/resampling step needed here, see `Agora.Media.Audio.Wav`'s
  moduledoc for why).

  ## Hallucination filtering

  `Agora.Media.Audio.UtteranceBuffer` already keeps *near-silent* audio
  from ever reaching this module (its energy gate — see its moduledoc).
  What that gate can't catch is Whisper hallucinating plausible-looking
  text on audio that has *some* energy but no real speech (background
  noise, breathing, a keyboard click) — confirmed hands-on: even 2s of
  true digital silence reliably decodes to `"Thank you.\\n"` from a
  base.en model, and `no_speech_prob` on that exact hallucinated segment
  was near zero, so trusting Whisper's own confidence score alone isn't
  sufficient. `response_format: "verbose_json"` gets us per-segment
  `no_speech_prob` as one signal; a small blocklist of the handful of
  stock phrases Whisper is well-known to hallucinate on low-content
  audio (see `@hallucination_blocklist`) is the second, catching exactly
  the case the confidence score misses.
  """

  require Logger

  alias Agora.Media.Audio.{Hallucination, Wav, WhisperServer}

  @sample_rate 48_000
  @channels 2
  @no_speech_threshold 0.65

  @doc """
  Transcribes one utterance. Returns `{:ok, text}` for real speech,
  `{:ok, nil}` when nothing survived hallucination filtering
  (deliberately not an error case — common, expected, not a failure),
  or `{:error, reason}` when the request itself failed.
  """
  @spec transcribe(binary()) :: {:ok, String.t() | nil} | {:error, term()}
  def transcribe(pcm) when is_binary(pcm) do
    case WhisperServer.base_url() do
      nil ->
        {:error, :unavailable}

      base_url ->
        wav = Wav.encode(pcm, @sample_rate, @channels)

        base_url
        |> Kernel.<>("/inference")
        |> Req.post(
          form_multipart: [
            file: {wav, filename: "utterance.wav", content_type: "audio/wav"},
            response_format: "verbose_json"
          ],
          receive_timeout: 30_000,
          retry: false
        )
        |> handle_response()
    end
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) do
    {:ok, extract_text(body)}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    Logger.warning(
      "Agora.Media.Audio.WhisperClient: whisper-server returned #{status}: #{inspect(body)}"
    )

    {:error, {:http_error, status}}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end

  defp extract_text(%{"segments" => segments}) when is_list(segments) and segments != [] do
    segments
    |> Enum.filter(&keep_segment?/1)
    |> Enum.map_join(" ", &String.trim(&1["text"] || ""))
    |> String.trim()
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp extract_text(%{"text" => text}) when is_binary(text) do
    trimmed = String.trim(text)
    if trimmed == "" or Hallucination.hallucinated?(trimmed), do: nil, else: trimmed
  end

  defp extract_text(_body), do: nil

  defp keep_segment?(%{"text" => text} = segment) do
    trimmed = String.trim(text || "")
    no_speech_prob = segment["no_speech_prob"] || 0.0

    trimmed != "" and no_speech_prob < @no_speech_threshold and
      not Hallucination.hallucinated?(trimmed)
  end

  defp keep_segment?(_), do: false
end
