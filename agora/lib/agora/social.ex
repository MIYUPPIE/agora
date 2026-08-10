defmodule Agora.Social do
  @moduledoc """
  The follow graph: Clings (following), Clingers (followers).

  Counts are always two indexed queries, never stored columns — they
  drift otherwise. Real-time updates work the same way: a cling/uncling
  broadcasts "something changed for this user", and subscribers re-query
  rather than trust a payload that could already be stale by the time a
  second event lands.
  """

  import Ecto.Query

  alias Agora.Notifications
  alias Agora.Social.Cling
  alias Agora.Repo

  @doc "People who follow this user."
  def clinger_count(user_id) do
    Cling |> where(clinged_id: ^user_id) |> Repo.aggregate(:count)
  end

  @doc "People this user follows."
  def cling_count(user_id) do
    Cling |> where(clinger_id: ^user_id) |> Repo.aggregate(:count)
  end

  @doc "IDs of people who follow this user — used to fan out new posts."
  def clinger_ids(user_id) do
    Cling |> where(clinged_id: ^user_id) |> select([c], c.clinger_id) |> Repo.all()
  end

  @doc "IDs of people this user follows — the feed is drawn from these."
  def clinged_ids(user_id) do
    Cling |> where(clinger_id: ^user_id) |> select([c], c.clinged_id) |> Repo.all()
  end

  def clinging?(clinger_id, clinged_id) do
    Cling
    |> where(clinger_id: ^clinger_id, clinged_id: ^clinged_id)
    |> Repo.exists?()
  end

  @doc """
  People who follow `user_id`, newest first, with their profile
  preloaded — the "Clingers" tab on the follow-list page.
  """
  def list_clingers(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    Cling
    |> where(clinged_id: ^user_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(clinger: :profile)
    |> Repo.all()
    |> Enum.map(& &1.clinger)
  end

  @doc """
  People `user_id` follows, newest first, with their profile preloaded
  — the "Clings" tab on the follow-list page.
  """
  def list_clings(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    Cling
    |> where(clinger_id: ^user_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(clinged: :profile)
    |> Repo.all()
    |> Enum.map(& &1.clinged)
  end

  @doc """
  The subset of `user_ids` that `viewer_id` clings to, as a `MapSet` —
  one query for a whole list of rows instead of one per row. `nil`
  viewer (not signed in) always yields an empty set.
  """
  def clinging_set(viewer_id, user_ids)
  def clinging_set(nil, _user_ids), do: MapSet.new()
  def clinging_set(_viewer_id, []), do: MapSet.new()

  def clinging_set(viewer_id, user_ids) do
    Cling
    |> where([c], c.clinger_id == ^viewer_id and c.clinged_id in ^user_ids)
    |> select([c], c.clinged_id)
    |> Repo.all()
    |> MapSet.new()
  end

  def cling(clinger_id, clinged_id) do
    %Cling{}
    |> Cling.changeset(%{clinger_id: clinger_id, clinged_id: clinged_id})
    |> Repo.insert()
    |> case do
      {:ok, cling} ->
        broadcast_stats(clinger_id)
        broadcast_stats(clinged_id)
        Notifications.notify(clinged_id, clinger_id, :cling)
        {:ok, cling}

      error ->
        error
    end
  end

  def uncling(clinger_id, clinged_id) do
    Cling
    |> where(clinger_id: ^clinger_id, clinged_id: ^clinged_id)
    |> Repo.delete_all()
    |> case do
      {1, _} ->
        broadcast_stats(clinger_id)
        broadcast_stats(clinged_id)
        :ok

      {0, _} ->
        {:error, :not_found}
    end
  end

  defp broadcast_stats(user_id) do
    Phoenix.PubSub.broadcast(Agora.PubSub, "user:#{user_id}:stats", {:stats_updated, user_id})
  end
end
