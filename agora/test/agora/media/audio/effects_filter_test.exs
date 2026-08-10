defmodule Agora.Media.Audio.EffectsFilterTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Agora.Media.Audio.{DB, EffectsChain, EffectsFilter, Params, PCM}
  alias Membrane.RawAudio
  alias Membrane.Testing

  @stream_format %RawAudio{
    sample_format: :s16le,
    sample_rate: EffectsChain.sample_rate(),
    channels: 2
  }

  defp sine_pcm(freq, amplitude, seconds) do
    n = round(seconds * EffectsChain.sample_rate())

    for i <- 0..(n - 1) do
      s = amplitude * :math.sin(2 * :math.pi() * freq * i / EffectsChain.sample_rate())
      {s, s}
    end
    |> PCM.encode_stereo()
  end

  defp start_pipeline!(initial_params \\ Params.default(), buffers) do
    spec =
      child(:source, %Testing.Source{output: buffers, stream_format: @stream_format})
      |> child(:effects, %EffectsFilter{initial_params: initial_params})
      |> child(:sink, Testing.Sink)

    Testing.Pipeline.start_link_supervised!(spec: spec)
  end

  test "passes stream format through as 48kHz s16le stereo raw audio" do
    pipeline = start_pipeline!([%Membrane.Buffer{payload: sine_pcm(440.0, 0.1, 0.02)}])

    assert_sink_stream_format(pipeline, :sink, %RawAudio{
      sample_format: :s16le,
      sample_rate: 48_000,
      channels: 2
    })

    Testing.Pipeline.terminate(pipeline)
  end

  test "processes a buffer and emits output of the same byte size" do
    payload = sine_pcm(440.0, 0.3, 0.02)
    pipeline = start_pipeline!([%Membrane.Buffer{payload: payload}])

    assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: out_payload})
    assert byte_size(out_payload) == byte_size(payload)

    Testing.Pipeline.terminate(pipeline)
  end

  test "an all-effects-disabled chain passes audio through essentially unchanged" do
    bypass_params =
      Params.default()
      |> Map.update!(:noise_gate, &Map.put(&1, :enabled, false))
      |> Map.update!(:eq, fn eq ->
        Map.new(eq, fn {band, p} -> {band, Map.put(p, :enabled, false)} end)
      end)
      |> Map.update!(:compressor, &Map.put(&1, :enabled, false))
      |> Map.update!(:reverb, &Map.put(&1, :enabled, false))
      |> Map.update!(:limiter, &Map.put(&1, :enabled, false))

    payload = sine_pcm(440.0, 0.3, 0.02)
    pipeline = start_pipeline!(bypass_params, [%Membrane.Buffer{payload: payload}])

    assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: out_payload})

    Enum.zip(PCM.decode_stereo(payload), PCM.decode_stereo(out_payload))
    |> Enum.each(fn {{il, ir}, {ol, or_}} ->
      assert_in_delta il, ol, 1.0e-3
      assert_in_delta ir, or_, 1.0e-3
    end)

    Testing.Pipeline.terminate(pipeline)
  end

  # This exercises the element's callbacks directly (handle_init ->
  # handle_parent_notification -> handle_buffer) rather than through a
  # live Membrane.Testing.Pipeline. The actual "does an update mid-stream
  # take effect on subsequent audio" behavior is already covered
  # end-to-end at the EffectsChain level (effects_chain_test.exs); what's
  # left to verify here is only the plumbing — that a parent notification
  # of {:update_params, changes} reaches EffectsChain.update_params/2.
  # Routing it through a real async pipeline would race Membrane's
  # `:auto` flow control (which eagerly pulls both buffers through before
  # a subsequently-sent notification is guaranteed to land between them)
  # against test-process message ordering — a timing assumption about the
  # scheduler, not about this element's logic.
  test "a live {:update_params, changes} parent notification is applied via EffectsChain.update_params/2" do
    flat_params =
      Params.default()
      |> Map.update!(:noise_gate, &Map.put(&1, :enabled, false))
      |> Map.update!(:eq, fn eq ->
        Map.new(eq, fn {band, p} -> {band, Map.put(p, :enabled, false)} end)
      end)
      |> Map.update!(:compressor, &Map.put(&1, :enabled, false))
      |> Map.update!(:reverb, &Map.put(&1, :enabled, false))
      |> Map.update!(:limiter, &Map.put(&1, :enabled, false))

    quiet_payload = sine_pcm(1000.0, DB.db_to_linear(-20.0), 0.02)
    buffer = %Membrane.Buffer{payload: quiet_payload}

    {[], state} = EffectsFilter.handle_init(%{}, %EffectsFilter{initial_params: flat_params})

    {[buffer: {:output, first_out}], state} =
      EffectsFilter.handle_buffer(:input, buffer, %{}, state)

    {[], state} =
      EffectsFilter.handle_parent_notification(
        {:update_params, %{input_gain_db: 12.0}},
        %{},
        state
      )

    assert state.chain.params.input_gain_db == 12.0

    {[buffer: {:output, second_out}], _state} =
      EffectsFilter.handle_buffer(:input, buffer, %{}, state)

    first_peak =
      first_out.payload
      |> PCM.decode_stereo()
      |> Enum.reduce(0.0, fn {l, _}, acc -> max(acc, abs(l)) end)

    second_peak =
      second_out.payload
      |> PCM.decode_stereo()
      |> Enum.reduce(0.0, fn {l, _}, acc -> max(acc, abs(l)) end)

    assert_in_delta DB.linear_to_db(second_peak) - DB.linear_to_db(first_peak), 12.0, 0.5
  end
end
