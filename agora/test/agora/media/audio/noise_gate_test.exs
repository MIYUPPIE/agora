defmodule Agora.Media.Audio.NoiseGateTest do
  use ExUnit.Case, async: true

  alias Agora.Media.Audio.{DB, NoiseGate}

  @sr 48_000

  @params %{threshold_db: -40.0, attack_ms: 2.0, release_ms: 50.0, hold_ms: 20.0, range_db: -60.0}

  defp run(gate, samples) do
    Enum.map_reduce(samples, gate, fn s, gate ->
      {gate, {l, _r}} = NoiseGate.process(gate, {s, s})
      {l, gate}
    end)
  end

  test "stays open (near-unity gain) for a signal above threshold" do
    gate = NoiseGate.new(@params, @sr)
    above_threshold = DB.db_to_linear(-20.0)
    samples = List.duplicate(above_threshold, 500)

    {outputs, _gate} = run(gate, samples)
    settled = Enum.drop(outputs, 100)

    Enum.each(settled, fn out -> assert_in_delta out, above_threshold, above_threshold * 0.05 end)
  end

  test "closes down to ~range_db after hold + release for signal below threshold" do
    gate = NoiseGate.new(@params, @sr)
    quiet = DB.db_to_linear(-70.0)
    samples = List.duplicate(quiet, 20_000)

    {outputs, _gate} = run(gate, samples)
    tail = Enum.take(outputs, -100)
    applied_gain_db = DB.linear_to_db(List.first(tail) / quiet)

    assert_in_delta applied_gain_db, @params.range_db, 1.0
  end

  test "hold keeps the gate open for hold_ms after level drops, before release begins" do
    gate = NoiseGate.new(@params, @sr)
    loud = DB.db_to_linear(-10.0)
    silent = 0.0000001

    loud_samples = List.duplicate(loud, 1000)
    # Fewer samples than hold_samples worth of time — should still read as "open".
    just_under_hold = List.duplicate(silent, DB.ms_to_samples(@params.hold_ms, @sr) - 5)

    {_out, gate} = run(gate, loud_samples)
    {tail_outputs, _gate} = run(gate, just_under_hold)

    # Gain should not have collapsed to range_db yet — still within hold window.
    last_gain_db = DB.linear_to_db(List.last(tail_outputs) / max(silent, 1.0e-12))
    assert abs(last_gain_db - @params.range_db) > 1.0
  end

  test "gain never exceeds unity (0dB) even for very loud input" do
    gate = NoiseGate.new(@params, @sr)
    very_loud = DB.db_to_linear(6.0)
    samples = List.duplicate(very_loud, 200)

    {outputs, _gate} = run(gate, samples)
    Enum.each(outputs, fn out -> assert out <= very_loud * 1.0001 end)
  end

  test "update_params/3 changes threshold without crashing and takes effect" do
    gate = NoiseGate.new(@params, @sr)
    updated = NoiseGate.update_params(gate, %{@params | threshold_db: -80.0}, @sr)

    quiet = DB.db_to_linear(-70.0)
    samples = List.duplicate(quiet, 500)
    {outputs, _gate} = run(updated, samples)

    # -70dB is now above the (lowered) -80dB threshold, so the gate should stay open.
    settled = Enum.drop(outputs, 100)
    Enum.each(settled, fn out -> assert_in_delta out, quiet, quiet * 0.1 end)
  end
end
