defmodule Agora.Media.Audio.PCM do
  @moduledoc """
  Conversions between interleaved little-endian s16 stereo PCM binaries
  (the wire format ffmpeg decodes to / encodes from) and lists of
  `{left, right}` float sample pairs normalized to [-1.0, 1.0] (the
  domain every DSP stage in `Agora.Media.Audio.EffectsChain` operates in).

  Normalizing to float on the way in means gain/threshold math expressed
  in dB (0 dBFS = amplitude 1.0) is correct regardless of bit depth, and
  intermediate stages (compressor makeup gain, reverb wet mix, ...) never
  have to reason about int16 overflow — only `encode_stereo/1` does, once,
  at the very end of the chain.
  """

  @int16_max 32_767
  @int16_min -32_768
  @full_scale 32_768.0

  @doc "Decodes interleaved s16le stereo PCM into a list of `{left, right}` floats in [-1.0, 1.0]."
  @spec decode_stereo(binary()) :: [{float(), float()}]
  def decode_stereo(binary) when is_binary(binary) do
    for <<l::signed-little-16, r::signed-little-16 <- binary>> do
      {l / @full_scale, r / @full_scale}
    end
  end

  @doc """
  Encodes a list of `{left, right}` float sample pairs back into
  interleaved s16le stereo PCM, clamping every sample to the valid
  16-bit range (the limiter stage keeps this a no-op in practice, but
  encode/1 stays safe on its own regardless of what feeds it).
  """
  @spec encode_stereo([{float(), float()}]) :: binary()
  def encode_stereo(frames) do
    for {l, r} <- frames, into: <<>> do
      <<to_int16(l)::signed-little-16, to_int16(r)::signed-little-16>>
    end
  end

  @spec to_int16(float()) :: integer()
  def to_int16(sample) do
    sample
    |> Kernel.*(@full_scale)
    |> round()
    |> clamp(@int16_min, @int16_max)
  end

  defp clamp(value, min, _max) when value < min, do: min
  defp clamp(value, _min, max) when value > max, do: max
  defp clamp(value, _min, _max), do: value
end
