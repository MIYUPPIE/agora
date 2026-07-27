defmodule Agora.Media.GatheringPipeline do
  @moduledoc """
  One supervised Membrane pipeline per live Gathering.

  Flow:  RTMP ingest (OBS / mobile encoder) -> demux -> AAC audio
         -> HLS packager -> Agora.Media.SegmentStorage (disk + DB + PubSub)

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

  NOTE: Membrane plugin APIs move between minor versions. This is written
  against membrane_core ~> 1.1, membrane_rtmp_plugin ~> 0.27,
  membrane_http_adaptive_stream_plugin ~> 0.18. Pin those in mix.exs and
  check each plugin's HexDocs livebook if a child spec option is renamed.
  """

  use Membrane.Pipeline

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

      # 3. Wire audio only: parse AAC out of the RTMP/FLV container and
      #    hand it to the packager.
      get_child(:source)
      |> via_out(:audio)
      |> child(:aac_parser, %Membrane.AAC.Parser{
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

    {[spec: spec], state}
  end

  # Broadcaster disconnected / ended the Gathering.
  @impl true
  def handle_element_end_of_stream(:hls, _pad, _ctx, state) do
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

  def handle_element_end_of_stream(_child, _pad, _ctx, state), do: {[], state}
end
