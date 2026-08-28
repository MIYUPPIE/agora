defmodule Agora.Media.Audio.WavTest do
  use ExUnit.Case, async: true

  alias Agora.Media.Audio.Wav

  test "produces a header ffmpeg accepts as a valid WAV, round-tripping the exact PCM back out" do
    pcm = for i <- 0..999, into: <<>>, do: <<rem(i * 37, 20_000)::signed-little-16>>
    wav = Wav.encode(pcm, 16_000, 1)

    tmp = Path.join(System.tmp_dir!(), "agora_wav_test_#{System.unique_integer([:positive])}.wav")
    File.write!(tmp, wav)

    try do
      {out, 0} =
        System.cmd(
          "ffmpeg",
          ~w(-hide_banner -loglevel error -y -i) ++
            [tmp] ++ ~w(-f s16le -ar 16000 -ac 1 pipe:1),
          stderr_to_stdout: false
        )

      assert out == pcm
    after
      File.rm(tmp)
    end
  end

  test "header fields (RIFF size, fmt block, data size) are correct for stereo 48kHz s16" do
    pcm = :crypto.strong_rand_bytes(4800 * 4)
    wav = Wav.encode(pcm, 48_000, 2)

    <<"RIFF", riff_size::little-32, "WAVE", "fmt ", 16::little-32, 1::little-16, 2::little-16,
      48_000::little-32, byte_rate::little-32, block_align::little-16, 16::little-16, "data",
      data_size::little-32, rest::binary>> = wav

    assert riff_size == 36 + byte_size(pcm)
    assert byte_rate == 48_000 * 2 * 2
    assert block_align == 2 * 2
    assert data_size == byte_size(pcm)
    assert rest == pcm
  end

  test "byte_size of the encoded WAV is exactly 44 bytes more than the input PCM" do
    pcm = :crypto.strong_rand_bytes(12_345)
    wav = Wav.encode(pcm, 44_100, 1, 16)

    assert byte_size(wav) == byte_size(pcm) + 44
  end
end
