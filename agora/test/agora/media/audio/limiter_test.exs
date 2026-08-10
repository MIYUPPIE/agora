defmodule Agora.Media.Audio.LimiterTest do
  use ExUnit.Case, async: true

  alias Agora.Media.Audio.{DB, Limiter}

  @sr 48_000
  @params %{ceiling_db: -1.0, attack_ms: 2.0, release_ms: 60.0}

  defp run(limiter, samples) do
    Enum.map_reduce(samples, limiter, fn s, l ->
      {l, out} = Limiter.process(l, s)
      {out, l}
    end)
  end

  test "never lets a single output sample exceed the ceiling, even during the lookahead warm-up" do
    limiter = Limiter.new(@params, @sr)
    ceiling = DB.db_to_linear(@params.ceiling_db)
    loud = {1.0, 1.0}
    samples = List.duplicate(loud, 2_000)

    {outputs, _limiter} = run(limiter, samples)

    Enum.each(outputs, fn {l, r} ->
      assert abs(l) <= ceiling + 1.0e-6
      assert abs(r) <= ceiling + 1.0e-6
    end)
  end

  test "a signal well under the ceiling passes through effectively unchanged (just delayed)" do
    limiter = Limiter.new(@params, @sr)
    quiet = DB.db_to_linear(-20.0)
    samples = List.duplicate({quiet, quiet}, 3_000)

    {outputs, _limiter} = run(limiter, samples)
    # Skip the lookahead warm-up (leading silence while the delay line fills).
    settled = Enum.drop(outputs, 500)

    Enum.each(settled, fn {l, r} ->
      assert_in_delta l, quiet, quiet * 0.02
      assert_in_delta r, quiet, quiet * 0.02
    end)
  end

  test "gain reduction kicks in for a signal above the ceiling and releases when it drops back" do
    limiter = Limiter.new(@params, @sr)
    ceiling = DB.db_to_linear(@params.ceiling_db)
    loud = {1.0, 1.0}
    quiet = {DB.db_to_linear(-30.0), DB.db_to_linear(-30.0)}

    loud_samples = List.duplicate(loud, 1000)
    quiet_samples = List.duplicate(quiet, 5000)

    {_out, limiter} = run(limiter, loud_samples)
    {tail_outputs, _limiter} = run(limiter, quiet_samples)

    {last_l, _} = List.last(tail_outputs)
    # Once fully released, a quiet signal should pass close to unity again.
    assert_in_delta last_l, elem(quiet, 0), elem(quiet, 0) * 0.05
    assert last_l < ceiling
  end

  test "update_params/3 changes the ceiling and takes effect" do
    limiter = Limiter.new(@params, @sr)
    tighter = Limiter.update_params(limiter, %{@params | ceiling_db: -6.0}, @sr)
    ceiling = DB.db_to_linear(-6.0)

    samples = List.duplicate({1.0, 1.0}, 2_000)
    {outputs, _limiter} = run(tighter, samples)

    Enum.each(outputs, fn {l, r} ->
      assert abs(l) <= ceiling + 1.0e-6
      assert abs(r) <= ceiling + 1.0e-6
    end)
  end
end
