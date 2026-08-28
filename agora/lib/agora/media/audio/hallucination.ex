defmodule Agora.Media.Audio.Hallucination do
  @moduledoc """
  Shared blocklist of stock phrases Whisper is well-known to hallucinate
  on low-content audio (silence, background noise, breathing, a stray
  click) — confirmed hands-on against a real base.en model: even 2s of
  true digital silence reliably decodes to `"Thank you.\\n"`, with
  `no_speech_prob` on that exact hallucinated segment near zero, so a
  confidence score alone isn't sufficient (see
  `Agora.Media.Audio.WhisperClient`'s moduledoc for the full story).

  Used by both the live path (`WhisperClient`, which additionally has
  `no_speech_prob` from `whisper-server`'s `verbose_json` to lean on)
  and the archival path (`WhisperCli`, whose plain `-oj` file output
  doesn't expose that score) so the two don't drift out of sync — a
  "final, accurate" transcript is a worse product than a live one if it
  can still contain stock hallucinated filler the live path already
  learned to filter.
  """

  @phrases [
    "thank you",
    "thanks for watching",
    "thanks for watching!",
    "please subscribe",
    "bye",
    "bye bye",
    "you",
    "[blank_audio]",
    "[silence]",
    "(silence)"
  ]

  @spec hallucinated?(String.t()) :: boolean()
  def hallucinated?(text) when is_binary(text) do
    normalized =
      text
      |> String.downcase()
      |> String.trim()
      |> String.trim_trailing(".")
      |> String.trim_trailing("!")
      |> String.trim()

    normalized in @phrases
  end
end
