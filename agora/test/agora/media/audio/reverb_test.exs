defmodule Agora.Media.Audio.ReverbTest do
  use ExUnit.Case, async: true

  alias Agora.Media.Audio.Reverb

  @sr 48_000
  @params %{mix: 0.3, room_size: 0.5, damping: 0.5}

  defp run(reverb, samples) do
    Enum.map_reduce(samples, reverb, fn s, r ->
      {r, out} = Reverb.process(r, s)
      {out, r}
    end)
  end

  test "mix: 0.0 is a bypass — output equals input exactly" do
    reverb = Reverb.new(%{@params | mix: 0.0}, @sr)
    samples = for i <- 1..500, do: {:math.sin(i / 10), :math.cos(i / 10)}

    {outputs, _reverb} = run(reverb, samples)

    Enum.zip(samples, outputs)
    |> Enum.each(fn {{il, ir}, {ol, or_}} ->
      assert_in_delta il, ol, 1.0e-9
      assert_in_delta ir, or_, 1.0e-9
    end)
  end

  test "an impulse produces a decaying tail that outlasts the impulse itself" do
    reverb = Reverb.new(@params, @sr)
    impulse = [{1.0, 1.0} | List.duplicate({0.0, 0.0}, 10_000)]

    {outputs, _reverb} = run(reverb, impulse)

    early_energy = outputs |> Enum.slice(0, 100) |> energy()
    tail_energy = outputs |> Enum.slice(2000, 100) |> energy()

    assert early_energy > 0.0
    assert tail_energy > 0.0
    # The tail must be quieter than right after the impulse (decaying, not sustaining).
    assert tail_energy < early_energy
  end

  test "the comb/allpass feedback network stays stable (bounded output) over a long impulse response" do
    reverb = Reverb.new(%{@params | room_size: 1.0, damping: 0.0}, @sr)
    impulse = [{1.0, 1.0} | List.duplicate({0.0, 0.0}, 48_000)]

    {outputs, _reverb} = run(reverb, impulse)

    max_abs = Enum.reduce(outputs, 0.0, fn {l, r}, acc -> max(acc, max(abs(l), abs(r))) end)
    refute max_abs != max_abs, "output contains NaN — feedback network diverged"
    assert max_abs < 5.0, "output grew unbounded (#{max_abs}) — feedback network is unstable"
  end

  test "higher mix produces more wet signal energy for the same input" do
    dry_ish = Reverb.new(%{@params | mix: 0.05}, @sr)
    wet_ish = Reverb.new(%{@params | mix: 0.5}, @sr)
    # Comb delay lines are ~1200+ samples at 48kHz — sample well past that
    # so the tank has actually cycled at least once before measuring.
    impulse = [{1.0, 1.0} | List.duplicate({0.0, 0.0}, 3000)]

    {dry_outputs, _} = run(dry_ish, impulse)
    {wet_outputs, _} = run(wet_ish, impulse)

    dry_tail = dry_outputs |> Enum.slice(1300, 200) |> energy()
    wet_tail = wet_outputs |> Enum.slice(1300, 200) |> energy()

    assert wet_tail > dry_tail
  end

  defp energy(frames) do
    Enum.reduce(frames, 0.0, fn {l, r}, acc -> acc + l * l + r * r end)
  end
end
