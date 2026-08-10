defmodule Agora.Media.Audio.Params do
  @moduledoc """
  Defaults, safe ranges, and validation for the live audio effects chain.

  This is the single source of truth every other entry point goes
  through — the LiveView control panel, the persisted preset, and
  `Agora.Media.Audio.EffectsChain` itself — so a value never reaches the
  DSP without first passing through `clamp/1`. That matters for more than
  UX: an unclamped `ratio` below 1.0 or ratio `attack_ms` <= 0 aren't just
  "weird settings", they're inputs the compressor/gate math above was
  never proven correct for. Clamping here is the trust boundary, the same
  way input validation would be for any other externally-controlled
  numeric input.

  Deliberately plain nested maps with atom keys, not a nested struct —
  the shape needs to recurse symmetrically against `@ranges` in
  `clamp/1`, round-trip through Jason for persistence, and merge partial
  updates from the UI, all of which are simpler without struct/map
  conversions at every level.
  """

  @default %{
    input_gain_db: 0.0,
    noise_gate: %{
      enabled: true,
      threshold_db: -50.0,
      attack_ms: 2.0,
      release_ms: 150.0,
      hold_ms: 50.0,
      range_db: -60.0
    },
    eq: %{
      highpass: %{enabled: true, freq: 90.0, q: 0.70},
      low_shelf: %{enabled: false, freq: 200.0, gain_db: 0.0},
      mid_peak: %{enabled: false, freq: 1000.0, gain_db: 0.0, q: 1.0},
      high_shelf: %{enabled: true, freq: 8000.0, gain_db: 2.0}
    },
    compressor: %{
      enabled: true,
      threshold_db: -18.0,
      ratio: 3.0,
      attack_ms: 10.0,
      release_ms: 150.0,
      knee_db: 6.0,
      makeup_gain_db: 3.0
    },
    reverb: %{enabled: false, mix: 0.12, room_size: 0.3, damping: 0.5},
    limiter: %{enabled: true, ceiling_db: -1.0, attack_ms: 5.0, release_ms: 60.0}
  }

  @ranges %{
    input_gain_db: {-24.0, 24.0},
    noise_gate: %{
      threshold_db: {-80.0, 0.0},
      attack_ms: {0.0, 200.0},
      release_ms: {5.0, 2000.0},
      hold_ms: {0.0, 1000.0},
      range_db: {-90.0, 0.0}
    },
    eq: %{
      highpass: %{freq: {20.0, 500.0}, q: {0.3, 5.0}},
      low_shelf: %{freq: {20.0, 1000.0}, gain_db: {-15.0, 15.0}},
      mid_peak: %{freq: {150.0, 8000.0}, gain_db: {-15.0, 15.0}, q: {0.3, 8.0}},
      high_shelf: %{freq: {1500.0, 18_000.0}, gain_db: {-15.0, 15.0}}
    },
    compressor: %{
      threshold_db: {-60.0, 0.0},
      ratio: {1.0, 20.0},
      attack_ms: {0.0, 200.0},
      release_ms: {5.0, 2000.0},
      knee_db: {0.0, 24.0},
      makeup_gain_db: {0.0, 24.0}
    },
    reverb: %{mix: {0.0, 0.6}, room_size: {0.0, 1.0}, damping: {0.0, 1.0}},
    limiter: %{ceiling_db: {-12.0, 0.0}, attack_ms: {0.0, 50.0}, release_ms: {5.0, 1000.0}}
  }

  @type t :: map()

  @spec default() :: t()
  def default, do: @default

  @doc "Range-clamps every known numeric leaf; passes booleans through unchanged; ignores unknown keys."
  @spec clamp(map()) :: t()
  def clamp(params) when is_map(params), do: clamp_tree(params, @default, @ranges)

  @doc """
  Deep-merges `changes` onto `base` and clamps the result. `changes` may
  be a partial, string- or atom-keyed map (as arrives from a JSON body or
  a LiveView form) — only keys that exist in the default shape are ever
  read; anything else is silently ignored rather than raising, since this
  sits directly on the boundary of "input a client controls".
  """
  @spec merge(t(), map()) :: t()
  def merge(base, changes) when is_map(base) and is_map(changes) do
    base |> merge_tree(changes, @default) |> clamp()
  end

  @doc "Safely loads a persisted/decoded map (e.g. from Jason.decode! on a jsonb column) back into the params shape."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: merge(@default, map)

  @doc "Plain map ready for jsonb/JSON persistence (already just a plain map, kept for symmetry with from_map/1)."
  @spec to_map(t()) :: map()
  def to_map(params) when is_map(params), do: params

  # ── Internal ──────────────────────────────────────────────────────────

  defp clamp_tree(value, default, ranges) when is_map(ranges) do
    Enum.reduce(default, %{}, fn {key, default_value}, acc ->
      current = Map.get(value, key, default_value)
      range_or_subtree = Map.get(ranges, key)

      Map.put(acc, key, clamp_value(current, default_value, range_or_subtree))
    end)
  end

  defp clamp_value(value, default_value, {min, max}) do
    case numeric(value) do
      {:ok, n} -> n |> Kernel.max(min) |> Kernel.min(max)
      :error -> default_value
    end
  end

  defp clamp_value(value, default_value, subtree) when is_map(subtree) do
    value = if is_map(value), do: value, else: %{}
    clamp_tree(value, default_value, subtree)
  end

  # Booleans (e.g. `enabled`) have no entry in @ranges — pass through if
  # boolean, otherwise fall back to the default rather than trust an
  # arbitrary client-supplied value in a boolean's place. HTML forms
  # (and therefore every checkbox in the LiveView effects panel) submit
  # booleans as the literal strings "true"/"false", never as actual
  # booleans, so those need to be recognized here too — not just real
  # booleans arriving via a programmatic API call.
  defp clamp_value(value, _default_value, nil) when is_boolean(value), do: value
  defp clamp_value("true", _default_value, nil), do: true
  defp clamp_value("false", _default_value, nil), do: false
  defp clamp_value(_value, default_value, nil), do: default_value

  defp numeric(n) when is_number(n), do: {:ok, n * 1.0}

  defp numeric(n) when is_binary(n) do
    case Float.parse(n) do
      {f, _rest} -> {:ok, f}
      :error -> :error
    end
  end

  defp numeric(_), do: :error

  defp merge_tree(base, changes, default) do
    Enum.reduce(default, %{}, fn {key, default_value}, acc ->
      incoming = fetch_either(changes, key)
      base_value = Map.get(base, key, default_value)

      merged =
        cond do
          is_map(default_value) and is_map(incoming) ->
            merge_tree(base_value, incoming, default_value)

          is_map(default_value) ->
            base_value

          not is_nil(incoming) ->
            incoming

          true ->
            base_value
        end

      Map.put(acc, key, merged)
    end)
  end

  defp fetch_either(map, key) do
    case Map.fetch(map, key) do
      {:ok, v} -> v
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
