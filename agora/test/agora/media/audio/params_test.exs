defmodule Agora.Media.Audio.ParamsTest do
  use ExUnit.Case, async: true

  alias Agora.Media.Audio.Params

  describe "default/0" do
    test "is already a valid, clamped shape" do
      assert Params.default() == Params.clamp(Params.default())
    end
  end

  describe "clamp/1" do
    test "clamps a value above the max down to the max" do
      params = put_in(Params.default().compressor.ratio, 999.0)
      clamped = Params.clamp(params)

      assert clamped.compressor.ratio == 20.0
    end

    test "clamps a value below the min up to the min" do
      params = put_in(Params.default().limiter.ceiling_db, -100.0)
      clamped = Params.clamp(params)

      assert clamped.limiter.ceiling_db == -12.0
    end

    test "leaves an in-range value unchanged" do
      params = put_in(Params.default().eq.mid_peak.gain_db, 5.0)
      clamped = Params.clamp(params)

      assert clamped.eq.mid_peak.gain_db == 5.0
    end

    test "falls back to the default for a non-numeric value in a numeric slot" do
      params = put_in(Params.default().noise_gate.threshold_db, "not a number")
      clamped = Params.clamp(params)

      assert clamped.noise_gate.threshold_db == Params.default().noise_gate.threshold_db
    end

    test "passes booleans through and rejects garbage values in a boolean slot" do
      enabled_false = put_in(Params.default().reverb.enabled, false)
      assert Params.clamp(enabled_false).reverb.enabled == false

      garbage = put_in(Params.default().reverb.enabled, "yes")
      assert Params.clamp(garbage).reverb.enabled == Params.default().reverb.enabled
    end

    test "coerces the string \"true\"/\"false\" to real booleans in a boolean slot" do
      # Every HTML checkbox (the effects panel's enabled toggles) submits
      # booleans as these literal strings, never as real booleans —
      # regression coverage for a bug where clamp/1 only recognized real
      # booleans and silently fell back to the default for "true"/"false"
      # strings, meaning checkbox toggles never took effect through a
      # real form submission despite passing every test that called
      # clamp/1 with an actual `true`/`false` value directly.
      turned_on = put_in(Params.default().reverb.enabled, "true")
      assert Params.clamp(turned_on).reverb.enabled == true

      turned_off = %{Params.default() | reverb: %{Params.default().reverb | enabled: true}}
      turned_off = put_in(turned_off.reverb.enabled, "false")
      assert Params.clamp(turned_off).reverb.enabled == false
    end

    test "fills in missing nested keys from the default rather than crashing" do
      sparse = %{compressor: %{ratio: 6.0}}
      clamped = Params.clamp(sparse)

      assert clamped.compressor.ratio == 6.0
      assert clamped.compressor.threshold_db == Params.default().compressor.threshold_db
      assert clamped.limiter == Params.default().limiter
    end

    test "silently ignores unknown top-level and nested keys" do
      params =
        Params.default() |> Map.put(:mystery_field, "hack") |> put_in([:compressor, :evil], true)

      clamped = Params.clamp(params)

      refute Map.has_key?(clamped, :mystery_field)
      refute Map.has_key?(clamped.compressor, :evil)
    end
  end

  describe "merge/2" do
    test "applies a partial atom-keyed change on top of the base" do
      merged = Params.merge(Params.default(), %{input_gain_db: 6.0})
      assert merged.input_gain_db == 6.0
      assert merged.compressor == Params.default().compressor
    end

    test "applies a partial string-keyed change (as arrives from a JSON/form payload)" do
      merged = Params.merge(Params.default(), %{"compressor" => %{"ratio" => 8.0}})
      assert merged.compressor.ratio == 8.0
      assert merged.compressor.threshold_db == Params.default().compressor.threshold_db
    end

    test "out-of-range values in the change are clamped, not passed through raw" do
      merged = Params.merge(Params.default(), %{"limiter" => %{"ceiling_db" => 50.0}})
      assert merged.limiter.ceiling_db == 0.0
    end

    test "a deeply nested single-field change doesn't disturb sibling fields" do
      merged = Params.merge(Params.default(), %{eq: %{high_shelf: %{gain_db: -3.0}}})

      assert merged.eq.high_shelf.gain_db == -3.0
      assert merged.eq.high_shelf.freq == Params.default().eq.high_shelf.freq
      assert merged.eq.highpass == Params.default().eq.highpass
    end
  end

  describe "from_map/1 (persisted jsonb round-trip)" do
    test "round-trips through Jason encode/decode with string keys" do
      original = Params.merge(Params.default(), %{input_gain_db: 4.5, compressor: %{ratio: 5.0}})

      json = Jason.encode!(Params.to_map(original))
      decoded = Jason.decode!(json)
      restored = Params.from_map(decoded)

      assert restored == original
    end

    test "never raises on completely malformed/attacker-controlled input" do
      malformed = %{"__proto__" => "x", "compressor" => "not a map", "eq" => nil, 123 => "y"}

      assert Params.from_map(malformed) == Params.default()
    end
  end
end
