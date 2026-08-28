defmodule Agora.Media.Audio.TranscriberTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Agora.Media.Audio.Transcriber
  alias Membrane.RawAudio
  alias Membrane.Testing

  @stream_format %RawAudio{sample_format: :s16le, sample_rate: 48_000, channels: 2}

  defp silence_pcm(ms) do
    n = trunc(ms / 1000 * 48_000)
    <<0::size(n * 2 * 16)>>
  end

  defp start_pipeline!(opts, buffers) do
    spec =
      child(:source, %Testing.Source{output: buffers, stream_format: @stream_format})
      |> child(:transcriber, struct!(Transcriber, [gathering_id: Ecto.UUID.generate()] ++ opts))
      |> child(:sink, Testing.Sink)

    Testing.Pipeline.start_link_supervised!(spec: spec)
  end

  describe "passthrough behavior" do
    test "emits 48kHz s16le stereo raw audio stream format, unchanged from input" do
      pipeline = start_pipeline!([], [%Membrane.Buffer{payload: silence_pcm(20)}])

      assert_sink_stream_format(pipeline, :sink, %RawAudio{
        sample_format: :s16le,
        sample_rate: 48_000,
        channels: 2
      })

      Testing.Pipeline.terminate(pipeline)
    end

    test "every input buffer passes through to output byte-for-byte" do
      payload = silence_pcm(20)
      pipeline = start_pipeline!([], [%Membrane.Buffer{payload: payload}])

      assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: ^payload})

      Testing.Pipeline.terminate(pipeline)
    end

    test "output is identical whether or not captioning is enabled — never alters audio" do
      payload = silence_pcm(20)
      pipeline = start_pipeline!([enabled: false], [%Membrane.Buffer{payload: payload}])

      assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: ^payload})

      Testing.Pipeline.terminate(pipeline)
    end
  end

  describe "handle_init/2" do
    test "defaults enabled to true and starts with an empty utterance buffer" do
      {[], state} = Transcriber.handle_init(%{}, %Transcriber{gathering_id: Ecto.UUID.generate()})

      assert state.enabled
      assert state.elapsed_ms == 0
      assert state.buffer.audio == <<>>
    end

    test "respects an explicit enabled: false option" do
      {[], state} =
        Transcriber.handle_init(%{}, %Transcriber{
          gathering_id: Ecto.UUID.generate(),
          enabled: false
        })

      refute state.enabled
    end
  end

  describe "handle_parent_notification/3 — the {:set_enabled, bool} toggle" do
    test "flips state.enabled" do
      {[], state} = Transcriber.handle_init(%{}, %Transcriber{gathering_id: Ecto.UUID.generate()})

      {[], state} = Transcriber.handle_parent_notification({:set_enabled, false}, %{}, state)
      refute state.enabled

      {[], state} = Transcriber.handle_parent_notification({:set_enabled, true}, %{}, state)
      assert state.enabled
    end

    test "an unrecognized notification is ignored, state untouched" do
      {[], state} = Transcriber.handle_init(%{}, %Transcriber{gathering_id: Ecto.UUID.generate()})
      assert {[], ^state} = Transcriber.handle_parent_notification(:something_else, %{}, state)
    end
  end

  describe "handle_buffer/4 while disabled" do
    test "still passes audio through, advances elapsed_ms, but never touches the utterance buffer" do
      {[], state} =
        Transcriber.handle_init(%{}, %Transcriber{
          gathering_id: Ecto.UUID.generate(),
          enabled: false
        })

      buffer = %Membrane.Buffer{payload: silence_pcm(20)}

      {[buffer: {:output, ^buffer}], new_state} =
        Transcriber.handle_buffer(:input, buffer, %{}, state)

      assert new_state.buffer == state.buffer
      assert_in_delta new_state.elapsed_ms, 20.0, 0.5
    end
  end

  describe "handle_buffer/4 while enabled" do
    test "feeds payload bytes into the utterance buffer and tracks elapsed time" do
      {[], state} = Transcriber.handle_init(%{}, %Transcriber{gathering_id: Ecto.UUID.generate()})

      buffer = %Membrane.Buffer{payload: silence_pcm(20)}

      {[buffer: {:output, ^buffer}], new_state} =
        Transcriber.handle_buffer(:input, buffer, %{}, state)

      # Leading silence before any speech is dropped by UtteranceBuffer
      # itself (see its moduledoc) — buffer stays empty, but elapsed
      # time still advances so later utterance offsets stay accurate.
      assert new_state.buffer.audio == <<>>
      assert_in_delta new_state.elapsed_ms, 20.0, 0.5
    end
  end
end
