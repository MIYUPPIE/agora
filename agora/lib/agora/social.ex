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

  def clinging?(clinger_id, clinged_id) do
    Cling
    |> where(clinger_id: ^clinger_id, clinged_id: ^clinged_id)
    |> Repo.exists?()
  end

  def cling(clinger_id, clinged_id) do
    %Cling{}
    |> Cling.changeset(%{clinger_id: clinger_id, clinged_id: clinged_id})
    |> Repo.insert()
    |> case do
      {:ok, cling} ->
        broadcast_stats(clinger_id)
        broadcast_stats(clinged_id)
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
