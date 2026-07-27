defmodule Agora.Workers.NotifyGatheringLive do
  @moduledoc """
  The growth loop: when a Gathering goes live, every one of the
  broadcaster's Clingers gets an in-app "X is live now" notification,
  wherever they currently are in the app. Web push / FCM can hang off
  the same fan-out later; for the MVP this is PubSub-only.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Agora.{Gatherings, Social}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"gathering_id" => gathering_id}}) do
    gathering = Gatherings.get!(gathering_id)

    for clinger_id <- Social.clinger_ids(gathering.user_id) do
      Phoenix.PubSub.broadcast(
        Agora.PubSub,
        "user:#{clinger_id}:notifications",
        {:gathering_live_notification, gathering.id, gathering.user.profile.display_name,
         gathering.title}
      )
    end

    :ok
  end
end
