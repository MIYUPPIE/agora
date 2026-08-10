defmodule Agora.Media.AudioEffects do
  @moduledoc """
  Public API for the live audio effects chain: reading/saving a
  broadcaster's preset, and pushing live parameter changes into a
  running `Agora.Media.GatheringPipeline` while a Gathering is live.

  This is the one place that knows about both halves of the feature —
  the persisted `Agora.Media.AudioEffectPreset` row and the live
  Membrane pipeline process — so callers (the LiveView control panel)
  never have to reach into either directly.
  """

  alias Agora.Media.Audio.Params
  alias Agora.Media.AudioEffectPreset
  alias Agora.Repo

  @doc "The broadcaster's saved effects params, or defaults if they've never customized anything."
  @spec get_params(Ecto.UUID.t()) :: Params.t()
  def get_params(user_id) do
    case Repo.get_by(AudioEffectPreset, user_id: user_id) do
      nil -> Params.default()
      %AudioEffectPreset{params: params} -> Params.from_map(params)
    end
  end

  @doc """
  Merges `changes` onto the user's saved params (defaults if they don't
  have a preset yet), clamps, persists (upsert), and — if `gathering_id`
  has a live pipeline right now — pushes the new params to it so the
  change is audible immediately, without dropping the stream.

  Returns `{:ok, params}` with the params that actually took effect
  (post-clamp), so the caller (a LiveView) can reconcile its own
  optimistic UI state against what was really applied.
  """
  @spec update_params(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, Params.t()} | {:error, Ecto.Changeset.t()}
  def update_params(gathering_id, user_id, changes) do
    new_params = get_params(user_id) |> Params.merge(changes)

    case save_preset(user_id, new_params) do
      {:ok, _preset} ->
        push_to_live_pipeline(gathering_id, changes)
        {:ok, new_params}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc "Whether a Gathering currently has a running (live) pipeline."
  @spec live?(Ecto.UUID.t()) :: boolean()
  def live?(gathering_id) do
    case Registry.lookup(Agora.Media.GatheringRegistry, gathering_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  defp push_to_live_pipeline(gathering_id, changes) do
    case Registry.lookup(Agora.Media.GatheringRegistry, gathering_id) do
      [{pid, _}] ->
        Membrane.Pipeline.call(pid, {:update_effect_params, changes})
        :ok

      [] ->
        :not_live
    end
  end

  defp save_preset(user_id, params) do
    attrs = %{user_id: user_id, params: Params.to_map(params)}

    case Repo.get_by(AudioEffectPreset, user_id: user_id) do
      nil -> %AudioEffectPreset{} |> AudioEffectPreset.changeset(attrs) |> Repo.insert()
      preset -> preset |> AudioEffectPreset.changeset(attrs) |> Repo.update()
    end
  end
end
