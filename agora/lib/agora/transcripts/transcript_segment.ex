defmodule Agora.Transcripts.TranscriptSegment do
  @moduledoc """
  One utterance of a Gathering's transcript.

  `source: :live` rows are written in near-real-time by
  `Agora.Media.Audio.Transcriber` while the Gathering is broadcasting —
  fast but occasionally imperfect. Once the Gathering ends,
  `Agora.Workers.ArchiveGathering` re-transcribes the full archived audio
  with a larger, more accurate model and replaces every `:live` row for
  that Gathering with `:final` ones in a single transaction (see
  `Agora.Transcripts.replace_final!/2`) — the live segments were always
  meant to be provisional captions, not the permanent record.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "transcript_segments" do
    belongs_to :gathering, Agora.Gatherings.Gathering

    field :source, Ecto.Enum, values: [:live, :final]
    field :seq, :integer
    field :start_ms, :integer
    field :end_ms, :integer
    field :text, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(segment, attrs) do
    segment
    |> cast(attrs, [:gathering_id, :source, :seq, :start_ms, :end_ms, :text])
    |> validate_required([:gathering_id, :source, :seq, :start_ms, :end_ms, :text])
  end
end
