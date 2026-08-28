defmodule AgoraWeb.TranscriptController do
  @moduledoc """
  Plain download endpoint for a Gathering's transcript as SubRip (.srt)
  captions — kept out of `GatheringLive.Show`/`.New` (which only render
  and PubSub-stream segments) since a file download is a one-shot GET,
  not LiveView state.
  """

  use AgoraWeb, :controller

  alias Agora.{Gatherings, Transcripts}

  def srt(conn, %{"id" => id}) do
    gathering = Gatherings.get!(id)
    segments = Transcripts.list_for_gathering(gathering.id)

    conn
    |> put_resp_content_type("application/x-subrip")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="#{gathering.id}.srt")
    )
    |> send_resp(200, Transcripts.to_srt(segments))
  end
end
