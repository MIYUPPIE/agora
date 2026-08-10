defmodule Agora.Media.GatheringPipeline do
  @moduledoc """
  One supervised Membrane pipeline per live Gathering.

  Flow:  RTMP ingest (OBS / mobile encoder) -> demux -> AAC audio
         -> decode to PCM -> live effects chain -> re-encode to AAC
         -> HLS packager -> Agora.Media.SegmentStorage (disk + DB + PubSub)

  The decode/effects/encode detour is `Agora.Media.Audio.AACDecoder` ->
  `Agora.Media.Audio.EffectsFilter` -> `Agora.Media.Audio.AACEncoder` —
  gain, noise gate, EQ, compressor, reverb, and limiter, applied live and
  controllable in real time via `handle_call/3` below, from
  `Agora.Media.AudioEffects`. It runs for every broadcaster regardless of
  how they connect (OBS/RTMP directly, or the browser-mic bridge via
  `Agora.Media.BrowserBroadcastBridge`, which itself just loops back into
  this same RTMP ingest) — see `Agora.Media.Audio.EffectsChain`'s
  moduledoc for the DSP chain itself, and `Agora.Media.Audio.FFmpegPort`
  for why AAC<->PCM conversion goes through ffmpeg rather than a native
  Membrane codec plugin.

  Design decisions:

    * Audio-only. We take only the :audio pad from the RTMP source. If a
      broadcaster sends video we simply ignore it (cheapest possible "audio
      platform" guarantee).

    * `target_window_duration: :infinity` + `persist?: true` keeps EVERY
      segment in the playlist for the whole Gathering. That is what makes
      listener-side "record from any point" and full replay free: the
      archive is a by-product of the live stream itself.

    * Segment duration of 4s is the sweet spot for radio-style audio:
      ~8-12s end-to-end latency and small enough segments that a
      "record" click has 4s granularity.
  """

  use Membrane.Pipeline

  alias Agora.Media.Audio.{AACDecoder, AACEncoder, EffectsFilter}
  alias Agora.Media.AudioEffects
  alias Membrane.HTTPAdaptiveStream.SinkBin
  alias Membrane.Time

  @segment_duration Time.seconds(4)

  # ── Public API ────────────────────────────────────────────────────────

  @doc """
  Started by Agora.Media.GatheringSupervisor when a broadcaster's RTMP
  client connects and the stream key is validated.
  """
  def start_link(opts) do
    Membrane.Pipeline.start_link(__MODULE__, opts,
      name: via_tuple(Keyword.fetch!(opts, :gathering_id))
    )
  end

  def via_tuple(gathering_id),
    do: {:via, Registry, {Agora.Media.GatheringRegistry, gathering_id}}

  # ── Pipeline ──────────────────────────────────────────────────────────

  @impl true
  def handle_init(_ctx, opts) do
    gathering_id = Keyword.fetch!(opts, :gathering_id)
    client_ref = Keyword.fetch!(opts, :client_ref)

    output_dir = Agora.Media.segment_dir(gathering_id)
    File.mkdir_p!(output_dir)

    %{user_id: user_id} = Agora.Gatherings.get!(gathering_id)
    initial_effect_params = AudioEffects.get_params(user_id)

    spec = [
      # 1. RTMP ingest. `client_ref` comes from Membrane.RTMPServer's
      #    handle_new_client callback (see Agora.Media.RTMPEndpoint).
      child(:source, %Membrane.RTMP.SourceBin{client_ref: client_ref}),

      # 2. HLS sink writing through our custom storage module.
      child(:hls, %SinkBin{
        manifest_name: "index",
        manifest_module: Membrane.HTTPAdaptiveStream.HLS,
        target_window_duration: :infinity,
        persist?: true,
        storage: %Agora.Media.SegmentStorage{
          gathering_id: gathering_id,
          directory: output_dir
        }
      }),

      # 3. Audio only: parse AAC out of the RTMP/FLV container, decode to
      #    raw PCM, run the live effects chain, re-encode to AAC, then
      #    re-parse the encoder's raw ADTS byte stream back into properly
      #    framed AAC access units (exactly the framing step the original
      #    single-parser pipeline did directly on the RTMP source) before
      #    handing off to the HLS packager.
      get_child(:source)
      |> via_out(:audio)
      |> child(:aac_parser_in, %Membrane.AAC.Parser{out_encapsulation: :ADTS})
      |> child(:aac_decoder, AACDecoder)
      |> child(:effects, %EffectsFilter{initial_params: initial_effect_params})
      |> child(:aac_encoder, AACEncoder)
      |> child(:aac_parser_out, %Membrane.AAC.Parser{
        out_encapsulation: :none,
        output_config: :esds
      })
      |> via_in(Pad.ref(:input, :audio),
        options: [encoding: :AAC, segment_duration: @segment_duration]
      )
      |> get_child(:hls)
    ]

    state = %{gathering_id: gathering_id, started_at: DateTime.utc_now()}

    # Flip the Gathering live in the DB and tell every Clinger's feed.
    Agora.Gatherings.mark_live!(gathering_id)

    Phoenix.PubSub.broadcast(
      Agora.PubSub,
      "gathering:#{gathering_id}",
      {:gathering_live, gathering_id}
    )

    # The growth loop: fan out "X is live now" to every Clinger.
    %{gathering_id: gathering_id}
    |> Agora.Workers.NotifyGatheringLive.new()
    |> Oban.insert()

    {[spec: spec], state}
  end

  # Live effects control — called synchronously by Agora.Media.AudioEffects
  # via Membrane.Pipeline.call/2 whenever a broadcaster moves a slider in
  # the effects panel while this Gathering is live. Forwarded to the
  # :effects child as a parent notification; see
  # Agora.Media.Audio.EffectsFilter.handle_parent_notification/3.
  @impl true
  def handle_call({:update_effect_params, changes}, _ctx, state) do
    {[notify_child: {:effects, {:update_params, changes}}, reply: :ok], state}
  end

  # Broadcaster disconnected / ended the Gathering.
  #
  # NOTE: `:hls` is a Bin (SinkBin), not a plain element — `Membrane.Bin`
  # has its *own* `handle_element_end_of_stream/4` callback, so when its
  # internal `:sink` child finishes, SinkBin's own implementation handles
  # that internally and (per its source) tells its parent via
  # `notify_parent: :end_of_stream`, which arrives here as a child
  # notification, not as `handle_element_end_of_stream(:hls, ...)` on the
  # pipeline. Confirmed by hand against a real RTMP push: the pipeline's
  # own end-of-stream callback for `:hls` never fired at all; this did.
  @impl true
  def handle_child_notification(:end_of_stream, :hls, _ctx, state) do
    Agora.Gatherings.mark_ended!(state.gathering_id)

    Phoenix.PubSub.broadcast(
      Agora.PubSub,
      "gathering:#{state.gathering_id}",
      {:gathering_ended, state.gathering_id}
    )

    # Archive job: uploads the full segment set to R2 and creates the
    # replay Post on the broadcaster's profile.
    %{gathering_id: state.gathering_id}
    |> Agora.Workers.ArchiveGathering.new()
    |> Oban.insert()

    {[terminate: :normal], state}
  end

  def handle_child_notification(_notification, _child, _ctx, state), do: {[], state}
end
