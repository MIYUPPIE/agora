defmodule Agora.Posts do
  @moduledoc """
  Posts (audio, image sets, tidings), reactions, and the feed.

  Audio posts have no manual "upload" entry point — they're created by
  Phase 4/5's ArchiveGathering worker when a live Gathering ends and its
  recording becomes a replay post. `create_audio_post/2` exists here so
  that worker (and tests) have something to call.

  Feed delivery is fan-out-on-write: posting broadcasts to every
  clinger's own `feed:<clinger_id>` topic, so a viewer subscribes to
  exactly one topic regardless of how many people they cling to.
  """

  import Ecto.Query

  alias Agora.Posts.{Comment, Post, PostMedia, Reaction}
  alias Agora.{Repo, Social}

  # ── Creating posts ──────────────────────────────────────────────────────

  def create_tiding(user_id, attrs) do
    %Post{}
    |> Post.changeset(Map.merge(attrs, %{"user_id" => user_id, "kind" => :tiding}))
    |> Repo.insert()
    |> after_create()
  end

  def create_image_post(user_id, attrs, image_uploads) when is_list(image_uploads) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :post,
      Post.changeset(%Post{}, Map.merge(attrs, %{"user_id" => user_id, "kind" => :image_set}))
    )
    |> Ecto.Multi.run(:media, fn repo, %{post: post} ->
      results =
        image_uploads
        |> Enum.with_index()
        |> Enum.map(fn {upload, index} ->
          %PostMedia{}
          |> PostMedia.changeset(%{
            post_id: post.id,
            kind: :image,
            url: upload.url,
            position: index,
            byte_size: upload.byte_size
          })
          |> repo.insert()
        end)

      case Enum.split_with(results, &match?({:ok, _}, &1)) do
        {oks, []} -> {:ok, Enum.map(oks, fn {:ok, m} -> m end)}
        {_, errors} -> {:error, errors}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{post: post}} -> after_create({:ok, post})
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Used by the Phase 4/5 ArchiveGathering worker — no UI calls this
  directly. `audio` is `%{url: ..., byte_size: ...}` for the already-
  uploaded recording.
  """
  def create_audio_post(user_id, attrs, %{url: url} = audio) do
    post_attrs = Map.merge(attrs, %{"user_id" => user_id, "kind" => :audio})

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:post, Post.changeset(%Post{}, post_attrs))
    |> Ecto.Multi.insert(:media, fn %{post: post} ->
      PostMedia.changeset(%PostMedia{}, %{
        post_id: post.id,
        kind: :audio,
        url: url,
        byte_size: audio[:byte_size]
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{post: post}} -> after_create({:ok, post})
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp after_create({:ok, post} = result) do
    fan_out_to_clingers(post)
    result
  end

  defp after_create(error), do: error

  defp fan_out_to_clingers(post) do
    for clinger_id <- Social.clinger_ids(post.user_id) do
      Phoenix.PubSub.broadcast(Agora.PubSub, "feed:#{clinger_id}", {:new_post, post.id})
    end
  end

  # ── Reading ──────────────────────────────────────────────────────────────

  def get_post!(id) do
    Post
    |> Repo.get!(id)
    |> Repo.preload([:media, user: :profile])
  end

  def count_for_user(user_id) do
    Post |> where(user_id: ^user_id) |> Repo.aggregate(:count)
  end

  @doc "Compact list of a single user's own posts, newest first — the profile hub feed."
  def list_for_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Post
    |> where(user_id: ^user_id)
    |> order_by(desc: :inserted_at, desc: :id)
    |> limit(^limit)
    |> preload(:media)
    |> Repo.all()
  end

  @doc "Posts from everyone `user_id` clings to, newest first — the main feed."
  def list_feed_for(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    clinged_ids = Social.clinged_ids(user_id)

    Post
    |> where([p], p.user_id in ^clinged_ids)
    |> order_by(desc: :inserted_at, desc: :id)
    |> limit(^limit)
    |> preload([:media, user: :profile])
    |> Repo.all()
  end

  # ── Reactions ────────────────────────────────────────────────────────────

  def reaction_counts(post_id) do
    Reaction
    |> where(post_id: ^post_id)
    |> group_by([r], r.kind)
    |> select([r], {r.kind, count(r.id)})
    |> Repo.all()
    |> Map.new()
    |> then(&%{heart: Map.get(&1, :heart, 0), torch: Map.get(&1, :torch, 0)})
  end

  def reacted?(user_id, post_id, kind) do
    Reaction
    |> where(user_id: ^user_id, post_id: ^post_id, kind: ^kind)
    |> Repo.exists?()
  end

  @doc "Adds the reaction if absent, removes it if present. Broadcasts either way."
  def toggle_reaction(user_id, post_id, kind) when kind in [:heart, :torch] do
    if reacted?(user_id, post_id, kind) do
      Reaction
      |> where(user_id: ^user_id, post_id: ^post_id, kind: ^kind)
      |> Repo.delete_all()
    else
      %Reaction{}
      |> Reaction.changeset(%{user_id: user_id, post_id: post_id, kind: kind})
      |> Repo.insert()
    end

    Phoenix.PubSub.broadcast(Agora.PubSub, "post:#{post_id}", {:reaction_updated, post_id})
    :ok
  end

  # ── Comments ─────────────────────────────────────────────────────────────

  def add_comment(user_id, post_id, body) do
    %Comment{}
    |> Comment.changeset(%{user_id: user_id, post_id: post_id, body: body})
    |> Repo.insert()
  end

  def list_comments(post_id) do
    Comment
    |> where(post_id: ^post_id)
    |> order_by(asc: :inserted_at)
    |> preload(user: :profile)
    |> Repo.all()
  end
end
