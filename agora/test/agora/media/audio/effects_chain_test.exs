defmodule Agora.Media.Audio.EffectsChainTest do
  use ExUnit.Case, async: true

  alias Agora.Media.Audio.{DB, EffectsChain, Params, PCM}

  @sr EffectsChain.sample_rate()

  defp sine_pcm(freq, amplitude, seconds) do
    n = round(seconds * @sr)

    for i <- 0..(n - 1) do
      s = amplitude * :math.sin(2 * :math.pi() * freq * i / @sr)
      {s, s}
    end
    |> PCM.encode_stereo()
  end

  describe "everything disabled" do
    test "is a pure passthrough (up to int16 quantization)" do
      all_off =
        Params.default()
        |> Map.update!(:noise_gate, &Map.put(&1, :enabled, false))
        |> Map.update!(:eq, fn eq ->
          Map.new(eq, fn {band, p} -> {band, Map.put(p, :enabled, false)} end)
        end)
        |> Map.update!(:compressor, &Map.put(&1, :enabled, false))
        |> Map.update!(:reverb, &Map.put(&1, :enabled, false))
        |> Map.update!(:limiter, &Map.put(&1, :enabled, false))

      chain = EffectsChain.new(all_off)
      input = sine_pcm(440.0, 0.3, 0.1)

      {_chain, output} = EffectsChain.process_buffer(chain, input)

      in_frames = PCM.decode_stereo(input)
      out_frames = PCM.decode_stereo(output)

      Enum.zip(in_frames, out_frames)
      |> Enum.each(fn {{il, ir}, {ol, or_}} ->
        assert_in_delta il, ol, 1.0e-3
        assert_in_delta ir, or_, 1.0e-3
      end)
    end
  end

  describe "default params on a realistic voice-like signal" do
    test "processes without crashing and never produces a sample outside the limiter ceiling" do
      chain = EffectsChain.new(Params.default())

      # A loud 200Hz tone (well above default gate/compressor thresholds and past the limiter ceiling).
      input = sine_pcm(200.0, 0.98, 1.0)

      {_chain, output} = EffectsChain.process_buffer(chain, input)
      ceiling = DB.db_to_linear(Params.default().limiter.ceiling_db)

      output
      |> PCM.decode_stereo()
      # Skip the limiter's lookahead warm-up window.
      |> Enum.drop(300)
      |> Enum.each(fn {l, r} ->
        assert abs(l) <= ceiling + 1.0e-3
        assert abs(r) <= ceiling + 1.0e-3
      end)
    end

    test "a very quiet signal below the noise gate threshold gets attenuated" do
      chain = EffectsChain.new(Params.default())
      quiet = DB.db_to_linear(-70.0)
      input = sine_pcm(200.0, quiet, 1.0)

      {_chain, output} = EffectsChain.process_buffer(chain, input)
      out_frames = PCM.decode_stereo(output)

      tail_peak =
        out_frames
        |> Enum.take(-4800)
        |> Enum.reduce(0.0, fn {l, r}, acc -> max(acc, max(abs(l), abs(r))) end)

      assert tail_peak < quiet * 0.5
    end
  end

  describe "update_params/2" do
    test "changing input_gain_db mid-stream changes output level for subsequent buffers" do
      flat_params =
        Params.default()
        |> Map.update!(:noise_gate, &Map.put(&1, :enabled, false))
        |> Map.update!(:compressor, &Map.put(&1, :enabled, false))
        |> Map.update!(:limiter, &Map.put(&1, :enabled, false))
        |> Map.update!(:reverb, &Map.put(&1, :enabled, false))
        |> Map.update!(:eq, fn eq ->
          Map.new(eq, fn {band, p} -> {band, Map.put(p, :enabled, false)} end)
        end)

      chain = EffectsChain.new(flat_params)
      quiet = DB.db_to_linear(-20.0)
      input = sine_pcm(1000.0, quiet, 0.05)

      {chain, first_output} = EffectsChain.process_buffer(chain, input)
      chain = EffectsChain.update_params(chain, %{input_gain_db: 12.0})
      {_chain, second_output} = EffectsChain.process_buffer(chain, input)

      first_peak =
        first_output
        |> PCM.decode_stereo()
        |> Enum.reduce(0.0, fn {l, _}, acc -> max(acc, abs(l)) end)

      second_peak =
        second_output
        |> PCM.decode_stereo()
        |> Enum.reduce(0.0, fn {l, _}, acc -> max(acc, abs(l)) end)

      assert_in_delta DB.linear_to_db(second_peak) - DB.linear_to_db(first_peak), 12.0, 0.5
    end

    test "does not raise across a full sweep of every parameter" do
      chain = EffectsChain.new(Params.default())

      chain =
        EffectsChain.update_params(chain, %{
          input_gain_db: -6.0,
          noise_gate: %{threshold_db: -35.0},
          eq: %{mid_peak: %{enabled: true, freq: 2000.0, gain_db: -4.0, q: 2.0}},
          compressor: %{ratio: 8.0, threshold_db: -12.0},
          reverb: %{enabled: true, mix: 0.3},
          limiter: %{ceiling_db: -3.0}
        })

      input = sine_pcm(300.0, 0.5, 0.2)
      {_chain, output} = EffectsChain.process_buffer(chain, input)

      assert byte_size(output) == byte_size(input)
    end
  end

  describe "process_buffer/2" do
    test "preserves PCM buffer byte size" do
      chain = EffectsChain.new(Params.default())
      input = sine_pcm(500.0, 0.4, 0.05)

      {_chain, output} = EffectsChain.process_buffer(chain, input)
      assert byte_size(output) == byte_size(input)
    end

    test "silence in stays silence-ish out (no self-oscillation from an idle chain)" do
      chain = EffectsChain.new(Params.default())
      silence = PCM.encode_stereo(List.duplicate({0.0, 0.0}, 48_000))

      {_chain, output} = EffectsChain.process_buffer(chain, silence)

      peak =
        output
        |> PCM.decode_stereo()
        |> Enum.reduce(0.0, fn {l, r}, acc -> max(acc, max(abs(l), abs(r))) end)

      assert peak < DB.db_to_linear(-50.0)
    end
  end
end
