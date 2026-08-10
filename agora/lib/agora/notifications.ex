defmodule Agora.Notifications do
  @moduledoc """
  Persisted, in-app notifications — cling (someone started clinging to
  you), comment, reaction, and gathering-live events. `notify/4` inserts
  a row and broadcasts `{:notification_created, notification}` on the
  recipient's `"user:<id>:notifications"` topic — the same topic
  `Workers.NotifyGatheringLive` already used for its ephemeral "live now"
  banner — so a connected LiveView can pick it up alongside that banner.

  Nobody gets notified about their own action (commenting on or
  reacting to your own post, etc.) — `notify/4` is a no-op when the
  actor is the recipient.
  """

  import Ecto.Query

  alias Agora.Notifications.Notification
  alias Agora.Repo

  @doc "Creates a notification for `recipient_id`, unless `actor_id` is the recipient themself."
  def notify(recipient_id, actor_id, type, opts \\ [])

  def notify(recipient_id, actor_id, _type, _opts) when recipient_id == actor_id do
    {:ok, nil}
  end

  def notify(recipient_id, actor_id, type, opts) do
    attrs = %{
      recipient_id: recipient_id,
      actor_id: actor_id,
      type: type,
      post_id: Keyword.get(opts, :post_id),
      gathering_id: Keyword.get(opts, :gathering_id),
      reaction_kind: Keyword.get(opts, :reaction_kind)
    }

    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, notification} ->
        notification = Repo.preload(notification, actor: :profile)

        Phoenix.PubSub.broadcast(
          Agora.PubSub,
          "user:#{recipient_id}:notifications",
          {:notification_created, notification}
        )

        {:ok, notification}

      error ->
        error
    end
  end

  @doc "Most recent notifications addressed to `user_id`, newest first."
  def list_for_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Notification
    |> where(recipient_id: ^user_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(actor: :profile)
    |> Repo.all()
  end

  @doc "How many of `user_id`'s notifications are unread — powers the nav bell badge."
  def unread_count(user_id) do
    Notification
    |> where([n], n.recipient_id == ^user_id and is_nil(n.read_at))
    |> Repo.aggregate(:count)
  end

  @doc "Marks every unread notification for `user_id` read in one query. Returns the number updated."
  def mark_all_read(user_id) do
    {count, _} =
      Notification
      |> where([n], n.recipient_id == ^user_id and is_nil(n.read_at))
      |> Repo.update_all(set: [read_at: DateTime.utc_now(:second)])

    count
  end
end
