defmodule Agora.Media.Audio.PCMTest do
  use ExUnit.Case, async: true

  alias Agora.Media.Audio.PCM

  describe "decode_stereo/1" do
    test "decodes interleaved s16le pairs into normalized float frames" do
      # +32767, -32768, 0, 16384 as s16le
      binary =
        <<32767::signed-little-16, -32768::signed-little-16, 0::signed-little-16,
          16384::signed-little-16>>

      assert [{l1, r1}, {l2, r2}] = PCM.decode_stereo(binary)
      assert_in_delta l1, 32767 / 32768, 1.0e-9
      assert_in_delta r1, -1.0, 1.0e-9
      assert_in_delta l2, 0.0, 1.0e-9
      assert_in_delta r2, 16384 / 32768, 1.0e-9
    end

    test "empty binary decodes to empty list" do
      assert PCM.decode_stereo(<<>>) == []
    end
  end

  describe "encode_stereo/1" do
    test "round-trips through decode_stereo/1 for representative values" do
      original =
        <<100::signed-little-16, -200::signed-little-16, 32767::signed-little-16,
          -32768::signed-little-16>>

      roundtripped = original |> PCM.decode_stereo() |> PCM.encode_stereo()

      assert byte_size(roundtripped) == byte_size(original)

      Enum.zip(PCM.decode_stereo(original), PCM.decode_stereo(roundtripped))
      |> Enum.each(fn {{l1, r1}, {l2, r2}} ->
        assert_in_delta l1, l2, 1.0e-4
        assert_in_delta r1, r2, 1.0e-4
      end)
    end

    test "clamps samples beyond [-1.0, 1.0] instead of wrapping/overflowing" do
      binary = PCM.encode_stereo([{2.0, -2.0}])
      assert [{l, r}] = PCM.decode_stereo(binary)

      assert_in_delta l, 1.0, 1.0e-3
      assert_in_delta r, -1.0, 1.0e-3
    end
  end

  describe "to_int16/1" do
    test "clamps at the int16 boundaries" do
      assert PCM.to_int16(10.0) == 32767
      assert PCM.to_int16(-10.0) == -32768
    end

    test "rounds to nearest integer" do
      assert PCM.to_int16(0.0) == 0
    end
  end
end
