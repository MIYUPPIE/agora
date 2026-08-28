defmodule Agora.Transcripts do
  @moduledoc """
  A Gathering's spoken-word transcript — live captions while it's
  broadcasting, replaced by one accurate final pass once it ends. See
  `Agora.Transcripts.TranscriptSegment` for the `:live` vs `:final`
  lifecycle and `Agora.Media.Audio.Transcriber` / `Agora.Workers.ArchiveGathering`
  for who writes each kind.
  """

  import Ecto.Query

  alias Agora.Notifications
  alias Agora.Repo
  alias Agora.Transcripts.TranscriptSegment

  @doc """
  Appends one live caption segment and broadcasts it on
  `"gathering:<id>:transcript"` — a topic separate from chat/lifecycle
  events (`"gathering:<id>"`) and segment events
  (`"gathering:<id>:segments"`) so a LiveView can subscribe to captions
  independently, same reasoning as those two.
  """
  @spec append_live_segment!(Ecto.UUID.t(), %{
          text: String.t(),
          start_ms: non_neg_integer(),
          end_ms: non_neg_integer()
        }) :: TranscriptSegment.t()
  def append_live_segment!(gathering_id, %{text: _, start_ms: _, end_ms: _} = attrs) do
    seq = next_seq(gathering_id, :live)

    segment =
      %TranscriptSegment{}
      |> TranscriptSegment.changeset(
        Map.merge(attrs, %{gathering_id: gathering_id, source: :live, seq: seq})
      )
      |> Repo.insert!()

    Phoenix.PubSub.broadcast(
      Agora.PubSub,
      "gathering:#{gathering_id}:transcript",
      {:transcript_segment, segment}
    )

    segment
  end

  @doc """
  Replaces every `:final` segment for `gathering_id` with `segments`
  (each `%{text:, start_ms:, end_ms:}`, in chronological order) in one
  transaction, then broadcasts `{:transcript_finalized, gathering_id}`
  so a connected LiveView can swap its provisional captions for the
  polished record. Called once, by `Agora.Workers.ArchiveGathering`,
  after the Gathering ends.
  """
  @spec replace_final!(Ecto.UUID.t(), [
          %{text: String.t(), start_ms: integer(), end_ms: integer()}
        ]) ::
          [TranscriptSegment.t()]
  def replace_final!(gathering_id, segments) do
    {:ok, inserted} =
      Repo.transaction(fn ->
        TranscriptSegment
        |> where(gathering_id: ^gathering_id, source: :final)
        |> Repo.delete_all()

        now = DateTime.utc_now(:second)

        segments
        |> Enum.with_index()
        |> Enum.map(fn {attrs, seq} ->
          %{
            id: Ecto.UUID.generate(),
            gathering_id: gathering_id,
            source: :final,
            seq: seq,
            start_ms: attrs.start_ms,
            end_ms: attrs.end_ms,
            text: attrs.text,
            inserted_at: now
          }
        end)
        |> then(&Repo.insert_all(TranscriptSegment, &1))

        list_for_gathering(gathering_id, :final)
      end)

    Phoenix.PubSub.broadcast(
      Agora.PubSub,
      "gathering:#{gathering_id}:transcript",
      {:transcript_finalized, gathering_id}
    )

    inserted
  end

  @doc "All segments for a Gathering, oldest first. `source` defaults to preferring :final over :live."
  def list_for_gathering(gathering_id, source \\ :any)

  def list_for_gathering(gathering_id, source) when source in [:live, :final] do
    TranscriptSegment
    |> where(gathering_id: ^gathering_id, source: ^source)
    |> order_by(asc: :seq)
    |> Repo.all()
  end

  def list_for_gathering(gathering_id, :any) do
    case list_for_gathering(gathering_id, :final) do
      [] -> list_for_gathering(gathering_id, :live)
      final -> final
    end
  end

  @doc "Whether a finished, accurate (:final) transcript exists for this Gathering."
  def finalized?(gathering_id) do
    TranscriptSegment
    |> where(gathering_id: ^gathering_id, source: :final)
    |> Repo.exists?()
  end

  @doc "Segments joined into a single readable block of text, in order."
  def full_text(segments) when is_list(segments) do
    segments |> Enum.map_join(" ", & &1.text) |> String.trim()
  end

  @doc "Renders segments as SubRip (.srt) captions — used by the transcript download link."
  @spec to_srt([TranscriptSegment.t()]) :: String.t()
  def to_srt(segments) when is_list(segments) do
    segments
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {segment, index} ->
      "#{index}\n#{srt_timestamp(segment.start_ms)} --> #{srt_timestamp(segment.end_ms)}\n#{segment.text}\n"
    end)
  end

  defp srt_timestamp(ms) when is_integer(ms) and ms >= 0 do
    hours = div(ms, 3_600_000)
    minutes = div(rem(ms, 3_600_000), 60_000)
    seconds = div(rem(ms, 60_000), 1_000)
    millis = rem(ms, 1_000)

    :io_lib.format("~2..0B:~2..0B:~2..0B,~3..0B", [hours, minutes, seconds, millis])
    |> IO.iodata_to_binary()
  end

  @doc """
  Notifies the broadcaster their finished transcript is ready — a
  self-notification (no other user caused this), so `actor_id: nil` per
  `Notifications.notify/4`'s "actor == recipient is a no-op" guard.
  """
  def notify_ready(user_id, gathering_id) do
    Notifications.notify(user_id, nil, :transcript_ready, gathering_id: gathering_id)
  end

  defp next_seq(gathering_id, source) do
    TranscriptSegment
    |> where(gathering_id: ^gathering_id, source: ^source)
    |> select([s], max(s.seq))
    |> Repo.one()
    |> case do
      nil -> 0
      max -> max + 1
    end
  end
end
