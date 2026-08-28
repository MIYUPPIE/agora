defmodule Agora.Media.Audio.Wav do
  @moduledoc """
  Wraps raw interleaved PCM in a canonical 44-byte WAV header — nothing
  else. Pure, dependency-free, the same "pure function over binaries"
  style as `Agora.Media.Audio.PCM`.

  Why this is enough, with no resampling/downmixing step of our own:
  whisper.cpp decodes uploaded audio through miniaudio configured for
  its target format (`ma_decoder_config_init(ma_format_f32, channels,
  WHISPER_SAMPLE_RATE)` in `common-whisper.cpp`), which resamples and
  downmixes *during* decode regardless of the source WAV's sample rate
  or channel count. Confirmed hands-on against a real `whisper-server`:
  posting this pipeline's native 48kHz stereo PCM (wrapped by
  `encode/3` below, untouched otherwise) transcribed correctly with no
  separate ffmpeg conversion step — one fewer subprocess spawned per
  utterance on the live-captioning path. (The archival path in
  `Agora.Media.Audio.WhisperCli` still shells out to ffmpeg — not for
  resampling, but because whisper.cpp's own decoder doesn't understand
  the AAC/m4a container `Agora.Media.build_clip/4` produces.)
  """

  @doc "Wraps `pcm` (interleaved sNNle PCM) in a canonical WAV header."
  @spec encode(binary(), pos_integer(), pos_integer(), 8 | 16 | 24 | 32) :: binary()
  def encode(pcm, sample_rate, channels, bits_per_sample \\ 16)
      when is_binary(pcm) and is_integer(sample_rate) and sample_rate > 0 and
             is_integer(channels) and channels > 0 do
    bytes_per_sample = div(bits_per_sample, 8)
    block_align = channels * bytes_per_sample
    byte_rate = sample_rate * block_align
    data_size = byte_size(pcm)

    header = <<
      "RIFF"::binary,
      36 + data_size::little-32,
      "WAVE"::binary,
      "fmt "::binary,
      16::little-32,
      1::little-16,
      channels::little-16,
      sample_rate::little-32,
      byte_rate::little-32,
      block_align::little-16,
      bits_per_sample::little-16,
      "data"::binary,
      data_size::little-32
    >>

    header <> pcm
  end
end
