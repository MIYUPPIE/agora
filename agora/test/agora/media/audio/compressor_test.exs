defmodule Agora.Media.Audio.CompressorTest do
  use ExUnit.Case, async: true

  alias Agora.Media.Audio.{Compressor, DB}

  @sr 48_000

  @params %{
    threshold_db: -20.0,
    ratio: 4.0,
    attack_ms: 5.0,
    release_ms: 100.0,
    knee_db: 0.0,
    makeup_gain_db: 0.0
  }

  describe "static_curve/4 (the gain-reduction math itself)" do
    test "no reduction below threshold" do
      assert Compressor.static_curve(-40.0, -20.0, 4.0, 0.0) == 0.0
    end

    test "exact hard-knee reduction above threshold: (level - threshold) * (1 - 1/ratio)" do
      # 10dB over threshold at ratio 4 -> 10 * (1 - 0.25) = 7.5dB of reduction.
      assert_in_delta Compressor.static_curve(-10.0, -20.0, 4.0, 0.0), 7.5, 1.0e-9
    end

    test "ratio 1.0 (no compression) never reduces regardless of level" do
      assert Compressor.static_curve(20.0, -20.0, 1.0, 0.0) == 0.0
    end

    test "soft knee is continuous with the linear region at both knee boundaries" do
      threshold = -20.0
      knee = 6.0
      ratio = 4.0

      knee_end = threshold + knee / 2

      at_end_via_knee = Compressor.static_curve(knee_end - 1.0e-6, threshold, ratio, knee)
      at_end_via_linear = Compressor.static_curve(knee_end + 1.0e-6, threshold, ratio, knee)

      assert_in_delta at_end_via_knee, at_end_via_linear, 1.0e-3
    end

    test "soft knee reduction is always non-negative inside the knee" do
      for level <- -25..-15 do
        reduction = Compressor.static_curve(level * 1.0, -20.0, 4.0, 6.0)
        assert reduction >= -1.0e-9
      end
    end
  end

  describe "process/2 ballistics + gain application" do
    test "a sustained tone above threshold settles to the expected reduced level" do
      compressor = Compressor.new(@params, @sr)
      input = DB.db_to_linear(0.0)
      samples = List.duplicate({input, input}, 20_000)

      {outputs, compressor} =
        Enum.map_reduce(samples, compressor, fn s, c ->
          {c, out} = Compressor.process(c, s)
          {out, c}
        end)

      {last_l, _last_r} = List.last(outputs)
      # 20dB over threshold at ratio 4 -> 15dB reduction -> output at -15dBFS.
      assert_in_delta DB.linear_to_db(last_l), -15.0, 0.5
      refute is_nil(compressor)
    end

    test "a quiet tone below threshold passes through at unity (no makeup gain configured)" do
      compressor = Compressor.new(@params, @sr)
      input = DB.db_to_linear(-40.0)
      samples = List.duplicate({input, input}, 5_000)

      {outputs, _compressor} =
        Enum.map_reduce(samples, compressor, fn s, c ->
          {c, out} = Compressor.process(c, s)
          {out, c}
        end)

      {last_l, _} = List.last(outputs)
      assert_in_delta last_l, input, input * 0.02
    end

    test "makeup_gain_db is applied uniformly, including to already-quiet signal" do
      params = %{@params | makeup_gain_db: 6.0}
      compressor = Compressor.new(params, @sr)
      input = DB.db_to_linear(-40.0)
      samples = List.duplicate({input, input}, 5_000)

      {outputs, _compressor} =
        Enum.map_reduce(samples, compressor, fn s, c ->
          {c, out} = Compressor.process(c, s)
          {out, c}
        end)

      {last_l, _} = List.last(outputs)
      assert_in_delta DB.linear_to_db(last_l) - DB.linear_to_db(input), 6.0, 0.2
    end

    test "silence in, silence out" do
      compressor = Compressor.new(@params, @sr)
      {_compressor, {l, r}} = Compressor.process(compressor, {0.0, 0.0})
      assert l == 0.0
      assert r == 0.0
    end
  end
end
