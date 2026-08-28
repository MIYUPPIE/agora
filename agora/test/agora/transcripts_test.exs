defmodule Agora.TranscriptsTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures

  alias Agora.{Gatherings, Notifications, Transcripts}

  defp gathering_fixture do
    user = user_fixture()
    {:ok, gathering} = Gatherings.create_gathering(user.id, %{"title" => "Sunday service"})
    gathering
  end

  describe "append_live_segment!/2" do
    test "inserts with source: :live and auto-incrementing seq, and broadcasts it" do
      gathering = gathering_fixture()
      Phoenix.PubSub.subscribe(Agora.PubSub, "gathering:#{gathering.id}:transcript")

      seg1 =
        Transcripts.append_live_segment!(gathering.id, %{text: "Hello", start_ms: 0, end_ms: 500})

      seg2 =
        Transcripts.append_live_segment!(gathering.id, %{
          text: "world",
          start_ms: 500,
          end_ms: 900
        })

      assert seg1.source == :live
      assert seg1.seq == 0
      assert seg2.seq == 1

      assert_receive {:transcript_segment, ^seg1}
      assert_receive {:transcript_segment, ^seg2}

      assert Transcripts.list_for_gathering(gathering.id, :live) == [seg1, seg2]
    end
  end

  describe "replace_final!/2" do
    test "deletes existing :live segments' visibility in favor of :final, broadcasts finalized, keeps :live rows intact" do
      gathering = gathering_fixture()

      Transcripts.append_live_segment!(gathering.id, %{
        text: "provisional",
        start_ms: 0,
        end_ms: 400
      })

      Phoenix.PubSub.subscribe(Agora.PubSub, "gathering:#{gathering.id}:transcript")

      final_segments = [
        %{text: "Accurate first sentence.", start_ms: 0, end_ms: 900},
        %{text: "Accurate second sentence.", start_ms: 900, end_ms: 1800}
      ]

      inserted = Transcripts.replace_final!(gathering.id, final_segments)

      assert_receive {:transcript_finalized, gathering_id}
      assert gathering_id == gathering.id

      assert Enum.map(inserted, & &1.text) == [
               "Accurate first sentence.",
               "Accurate second sentence."
             ]

      assert Enum.map(inserted, & &1.seq) == [0, 1]
      assert Transcripts.finalized?(gathering.id)
      # :live provisional segment is untouched, just no longer what list_for_gathering/1 prefers
      assert [%{text: "provisional"}] = Transcripts.list_for_gathering(gathering.id, :live)
      assert Transcripts.list_for_gathering(gathering.id) == inserted
    end

    test "calling it twice replaces the :final set rather than appending to it" do
      gathering = gathering_fixture()

      Transcripts.replace_final!(gathering.id, [%{text: "draft", start_ms: 0, end_ms: 500}])

      final =
        Transcripts.replace_final!(gathering.id, [%{text: "polished", start_ms: 0, end_ms: 500}])

      assert Enum.map(final, & &1.text) == ["polished"]

      assert Enum.map(Transcripts.list_for_gathering(gathering.id, :final), & &1.text) == [
               "polished"
             ]
    end
  end

  describe "list_for_gathering/2 default (:any)" do
    test "prefers :final over :live when both exist" do
      gathering = gathering_fixture()

      Transcripts.append_live_segment!(gathering.id, %{text: "live one", start_ms: 0, end_ms: 400})

      Transcripts.replace_final!(gathering.id, [%{text: "final one", start_ms: 0, end_ms: 400}])

      assert [%{text: "final one", source: :final}] = Transcripts.list_for_gathering(gathering.id)
    end

    test "falls back to :live when no :final transcript exists yet" do
      gathering = gathering_fixture()

      Transcripts.append_live_segment!(gathering.id, %{text: "live one", start_ms: 0, end_ms: 400})

      assert [%{text: "live one", source: :live}] = Transcripts.list_for_gathering(gathering.id)
    end

    test "empty list when nothing has been transcribed yet" do
      gathering = gathering_fixture()
      assert Transcripts.list_for_gathering(gathering.id) == []
      refute Transcripts.finalized?(gathering.id)
    end
  end

  describe "full_text/1" do
    test "joins segment texts with a single space, trimmed" do
      segments = [%{text: "Hello"}, %{text: "world."}]
      assert Transcripts.full_text(segments) == "Hello world."
    end

    test "empty list yields an empty string" do
      assert Transcripts.full_text([]) == ""
    end
  end

  describe "to_srt/1" do
    test "renders standard SubRip format with 1-based index and comma-decimal timestamps" do
      segments = [
        %{start_ms: 0, end_ms: 1_500, text: "Hello there."},
        %{start_ms: 1_500, end_ms: 63_250, text: "Second line."}
      ]

      srt = Transcripts.to_srt(segments)

      assert srt == """
             1
             00:00:00,000 --> 00:00:01,500
             Hello there.

             2
             00:00:01,500 --> 00:01:03,250
             Second line.
             """
    end

    test "empty list yields an empty string" do
      assert Transcripts.to_srt([]) == ""
    end
  end

  describe "notify_ready/2" do
    test "creates a :transcript_ready notification for the broadcaster (self-notification, actor is nil)" do
      gathering = gathering_fixture()

      assert {:ok, notification} = Transcripts.notify_ready(gathering.user_id, gathering.id)
      assert notification.type == :transcript_ready
      assert notification.recipient_id == gathering.user_id
      assert notification.actor_id == nil
      assert notification.gathering_id == gathering.id

      assert [%{type: :transcript_ready}] = Notifications.list_for_user(gathering.user_id)
    end
  end
end
