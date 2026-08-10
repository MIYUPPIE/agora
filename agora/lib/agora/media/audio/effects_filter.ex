defmodule Agora.Media.Audio.EffectsFilter do
  @moduledoc """
  Membrane filter wrapping `Agora.Media.Audio.EffectsChain`. Sits between
  the AAC->PCM decode stage and the PCM->AAC encode stage in
  `Agora.Media.GatheringPipeline`, applying the live effects chain to
  every raw-audio buffer that passes through.

  Live parameter changes arrive as a parent notification —
  `Membrane.Pipeline.notify_child(pipeline, :effects, {:update_params, changes})`
  — rather than a pad option, precisely because pad options are fixed at
  spec time and this chain needs to change *while the Gathering is live*,
  without dropping the stream or restarting any child.
  """

  use Membrane.Filter

  alias Agora.Media.Audio.EffectsChain
  alias Membrane.RawAudio

  @stream_format %RawAudio{
    sample_format: :s16le,
    sample_rate: EffectsChain.sample_rate(),
    channels: 2
  }

  def_input_pad(:input, accepted_format: %RawAudio{sample_format: :s16le}, flow_control: :auto)
  def_output_pad(:output, accepted_format: %RawAudio{sample_format: :s16le}, flow_control: :auto)

  def_options(
    initial_params: [
      spec: map(),
      default: Agora.Media.Audio.Params.default(),
      description: "Effects chain parameters to start with (see `Agora.Media.Audio.Params`)."
    ]
  )

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{chain: EffectsChain.new(opts.initial_params)}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, @stream_format}], state}
  end

  @impl true
  def handle_stream_format(:input, _stream_format, _ctx, state) do
    {[stream_format: {:output, @stream_format}], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    {chain, payload} = EffectsChain.process_buffer(state.chain, buffer.payload)
    {[buffer: {:output, %{buffer | payload: payload}}], %{state | chain: chain}}
  end

  @impl true
  def handle_parent_notification({:update_params, changes}, _ctx, state) when is_map(changes) do
    {[], %{state | chain: EffectsChain.update_params(state.chain, changes)}}
  end

  def handle_parent_notification(_other, _ctx, state), do: {[], state}
end
