defmodule Agora.Media.Audio.BiquadTest do
  use ExUnit.Case, async: true

  alias Agora.Media.Audio.Biquad

  @sr 48_000

  # Runs a filter over enough impulse-plus-noise-free sine cycles for its
  # transient to settle, then measures the steady-state output amplitude
  # relative to input amplitude — i.e. the *actual* time-domain gain a
  # broadcaster's ear would hear at that frequency, entirely independent
  # of `magnitude_response/3`'s frequency-domain math.
  defp settled_gain_db(coeffs, freq, sample_rate \\ @sr) do
    cycles = 40
    n = round(cycles * sample_rate / freq)
    settle = div(n, 2)

    {outputs, _state} =
      Enum.map_reduce(0..(n - 1), Biquad.new_state(), fn i, state ->
        x = :math.sin(2 * :math.pi() * freq * i / sample_rate)
        Biquad.process(coeffs, state, x)
      end)

    measured = outputs |> Enum.drop(settle)
    peak = Enum.reduce(measured, 0.0, fn y, acc -> max(acc, abs(y)) end)
    Agora.Media.Audio.DB.linear_to_db(peak)
  end

  describe "process/3 direct form I recursion" do
    test "identity filter passes signal through unchanged" do
      coeffs = Biquad.identity()
      state = Biquad.new_state()

      {y1, state} = Biquad.process(coeffs, state, 0.5)
      {y2, _state} = Biquad.process(coeffs, state, -0.25)

      assert_in_delta y1, 0.5, 1.0e-9
      assert_in_delta y2, -0.25, 1.0e-9
    end

    test "state threads x1/x2/y1/y2 correctly across calls" do
      coeffs = %Biquad{b0: 1.0, b1: 1.0, b2: 0.0, a1: 0.0, a2: 0.0}
      state = Biquad.new_state()

      {y1, state} = Biquad.process(coeffs, state, 1.0)
      assert_in_delta y1, 1.0, 1.0e-9

      {y2, _state} = Biquad.process(coeffs, state, 2.0)
      # y2 = b0*x2 + b1*x1 = 1*2.0 + 1*1.0 = 3.0
      assert_in_delta y2, 3.0, 1.0e-9
    end
  end

  describe "highpass/3" do
    test "attenuates well below cutoff and passes well above it" do
      coeffs = Biquad.highpass(200.0, 0.707, @sr)

      below = settled_gain_db(coeffs, 40.0)
      above = settled_gain_db(coeffs, 4000.0)

      assert below < -15.0
      assert_in_delta above, 0.0, 0.5
    end

    test "is approximately -3dB at the cutoff frequency" do
      coeffs = Biquad.highpass(500.0, 0.707, @sr)
      mag_db = Agora.Media.Audio.DB.linear_to_db(Biquad.magnitude_response(coeffs, 500.0, @sr))

      assert_in_delta mag_db, -3.01, 0.1
    end

    test "time-domain settled gain agrees with frequency-domain magnitude_response/3" do
      coeffs = Biquad.highpass(150.0, 0.9, @sr)

      for freq <- [50.0, 150.0, 500.0, 3000.0] do
        time_domain = settled_gain_db(coeffs, freq)

        freq_domain =
          Agora.Media.Audio.DB.linear_to_db(Biquad.magnitude_response(coeffs, freq, @sr))

        assert_in_delta time_domain, freq_domain, 0.5, "mismatch at #{freq}Hz"
      end
    end
  end

  describe "lowpass/3" do
    test "passes well below cutoff and attenuates well above it" do
      coeffs = Biquad.lowpass(2000.0, 0.707, @sr)

      below = settled_gain_db(coeffs, 200.0)
      above = settled_gain_db(coeffs, 16_000.0)

      assert_in_delta below, 0.0, 0.5
      assert above < -15.0
    end
  end

  describe "peaking/4" do
    test "boosts the target frequency and leaves DC-ish far frequencies near unity" do
      coeffs = Biquad.peaking(1000.0, 12.0, 1.0, @sr)

      at_target = settled_gain_db(coeffs, 1000.0)
      far_below = settled_gain_db(coeffs, 60.0)
      far_above = settled_gain_db(coeffs, 18_000.0)

      assert_in_delta at_target, 12.0, 0.3
      assert_in_delta far_below, 0.0, 0.5
      assert_in_delta far_above, 0.0, 0.5
    end

    test "cuts the target frequency for negative gain" do
      coeffs = Biquad.peaking(1000.0, -12.0, 1.0, @sr)
      at_target = settled_gain_db(coeffs, 1000.0)

      assert_in_delta at_target, -12.0, 0.3
    end

    test "0dB gain is the identity filter (within floating point tolerance)" do
      coeffs = Biquad.peaking(1000.0, 0.0, 1.0, @sr)
      at_target = settled_gain_db(coeffs, 1000.0)

      assert_in_delta at_target, 0.0, 0.05
    end
  end

  describe "low_shelf/3" do
    test "boosts below the corner and leaves far-above frequencies at unity" do
      coeffs = Biquad.low_shelf(200.0, 9.0, @sr)

      low = settled_gain_db(coeffs, 40.0)
      high = settled_gain_db(coeffs, 10_000.0)

      assert_in_delta low, 9.0, 0.5
      assert_in_delta high, 0.0, 0.5
    end
  end

  describe "high_shelf/3" do
    test "boosts above the corner and leaves far-below frequencies at unity" do
      coeffs = Biquad.high_shelf(6000.0, 6.0, @sr)

      high = settled_gain_db(coeffs, 18_000.0)
      low = settled_gain_db(coeffs, 100.0)

      assert_in_delta high, 6.0, 0.5
      assert_in_delta low, 0.0, 0.5
    end

    test "cuts above the corner for negative gain" do
      coeffs = Biquad.high_shelf(6000.0, -8.0, @sr)
      high = settled_gain_db(coeffs, 18_000.0)

      assert_in_delta high, -8.0, 0.5
    end
  end

  describe "magnitude_response/3 stability" do
    test "every designed filter type stays bounded (no NaN/inf, no runaway gain) across the audible range" do
      filters = [
        Biquad.highpass(90.0, 0.707, @sr),
        Biquad.lowpass(12_000.0, 0.707, @sr),
        Biquad.peaking(1000.0, 15.0, 4.0, @sr),
        Biquad.low_shelf(150.0, -15.0, @sr),
        Biquad.high_shelf(9000.0, 15.0, @sr)
      ]

      freqs = [20.0, 100.0, 500.0, 1000.0, 5000.0, 15_000.0, 20_000.0]

      for coeffs <- filters, freq <- freqs do
        mag = Biquad.magnitude_response(coeffs, freq, @sr)
        refute mag != mag, "NaN magnitude for #{inspect(coeffs)} at #{freq}Hz"
        assert mag < 100.0, "unbounded magnitude for #{inspect(coeffs)} at #{freq}Hz: #{mag}"
      end
    end
  end
end
