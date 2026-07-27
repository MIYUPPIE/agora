defmodule Agora.MediaTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures
  import Agora.MediaFixtures

  alias Agora.{Gatherings, Media}

  setup do
    user = user_fixture()
    {:ok, gathering} = Gatherings.create_gathering(user.id, %{"title" => "Test gathering"})
    %{gathering: gathering}
  end

  describe "insert_segment! / current_sequence / segments_in_range" do
    test "current_sequence is 0 with no segments, then tracks the max", %{gathering: gathering} do
      assert Media.current_sequence(gathering.id) == 0

      Media.insert_segment!(%{gathering_id: gathering.id, sequence: 0, filename: "a.m4s"})
      Media.insert_segment!(%{gathering_id: gathering.id, sequence: 1, filename: "b.m4s"})

      assert Media.current_sequence(gathering.id) == 1
    end

    test "segments_in_range is inclusive on both ends and ordered", %{gathering: gathering} do
      for seq <- 0..4 do
        Media.insert_segment!(%{
          gathering_id: gathering.id,
          sequence: seq,
          filename: "s#{seq}.m4s"
        })
      end

      segs = Media.segments_in_range(gathering.id, 1, 3)
      assert Enum.map(segs, & &1.sequence) == [1, 2, 3]
    end

    test "duplicate sequence for the same gathering is rejected by the unique index", %{
      gathering: gathering
    } do
      Media.insert_segment!(%{gathering_id: gathering.id, sequence: 0, filename: "a.m4s"})

      assert_raise Ecto.InvalidChangesetError, fn ->
        Media.insert_segment!(%{gathering_id: gathering.id, sequence: 0, filename: "b.m4s"})
      end
    end
  end

  describe "build_clip/4" do
    test "returns :no_segments when the range is empty", %{gathering: gathering} do
      assert Media.build_clip(gathering.id, 0, 5) == {:error, :no_segments}
    end

    test "concatenates real fMP4 fragments into a single valid, correctly-timed file", %{
      gathering: gathering
    } do
      write_synthetic_segments!(gathering.id, duration_seconds: 2)

      assert {:ok, path, byte_size} = Media.build_clip(gathering.id, 0, 2)

      on_exit(fn -> File.rm_rf(Path.dirname(path)) end)

      assert byte_size > 0
      assert byte_size == File.stat!(path).size

      duration_ms = Media.ffprobe_duration_ms(path)
      assert_in_delta duration_ms, 2000, 200
    end

    test "the mp3 format path re-encodes the concatenated file", %{gathering: gathering} do
      write_synthetic_segments!(gathering.id, duration_seconds: 1)

      assert {:ok, path, _byte_size} = Media.build_clip(gathering.id, 0, 2, "mp3")
      on_exit(fn -> File.rm_rf(Path.dirname(path)) end)

      assert Path.extname(path) == ".mp3"
      assert Media.ffprobe_duration_ms(path)
    end

    test "a clip starting mid-stream reports its own length, not the stream's absolute position",
         %{
           gathering: gathering
         } do
      # ~10 one-second segments; build a clip from just the LAST two.
      # Before the -avoid_negative_ts make_zero fix, fMP4's absolute
      # (stream-original) timestamps leaked through: the container-level
      # duration read back as roughly this clip's *position* in the
      # original stream (~8-9s) instead of the ~2s actually in the file
      # — confirmed against a real listener recording during manual
      # testing, where a mid-stream "Record from now" clip reported a
      # 25s duration in the file's own metadata despite being a 10KB,
      # ~1s recording.
      write_synthetic_segments!(gathering.id, duration_seconds: 10)
      last_two = Media.segments_in_range(gathering.id, 0, 20) |> Enum.take(-2)
      [first_seq, last_seq] = Enum.map(last_two, & &1.sequence)
      assert first_seq >= 6, "expected this clip to start well after the stream's beginning"

      assert {:ok, path, _byte_size} = Media.build_clip(gathering.id, first_seq, last_seq)
      on_exit(fn -> File.rm_rf(Path.dirname(path)) end)

      # Read straight off container metadata — no decode — exactly what
      # a real audio player's seek bar would show. The buggy behavior
      # would put this near (first_seq * 1000)ms; the fix keeps it near
      # the clip's own ~2s span regardless of where it sits in the
      # original stream.
      duration_ms = Media.ffprobe_duration_ms(path)
      assert duration_ms < 4000
      assert duration_ms > 300
    end
  end

  describe "ffprobe_duration_ms/1" do
    test "returns nil for a nonsense path" do
      assert Media.ffprobe_duration_ms("/no/such/file.m4a") == nil
    end
  end
end
