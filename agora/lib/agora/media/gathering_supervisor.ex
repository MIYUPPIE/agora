defmodule Agora.Media.GatheringSupervisor do
  @moduledoc "DynamicSupervisor owning one GatheringPipeline per live stream."
  use DynamicSupervisor

  def start_link(init_arg),
    do: DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)

  @impl true
  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_gathering(gathering_id, client_ref) do
    # restart: :temporary is load-bearing, not decorative. Membrane.Pipeline's
    # own child_spec defaults to :permanent (like any GenServer), and a
    # DynamicSupervisor honors that regardless of *why* the child exited —
    # including our own deliberate `terminate: :normal` when a Gathering ends.
    # Confirmed against a real RTMP stream: without this, the instant a
    # broadcaster's stream ends, the supervisor "resurrects" the pipeline
    # with the same now-dead client_ref, which calls mark_live! again and
    # flips the Gathering's status back to :live — a zombie that can never
    # actually end again, since no more real RTMP data will ever arrive on
    # that dead connection. A Gathering's pipeline should run exactly once
    # per RTMP connection; a new connection gets a fresh one through
    # RTMPEndpoint's own stream-key validation, never an automatic restart.
    child_spec = %{
      id: {__MODULE__, gathering_id},
      start:
        {Agora.Media.GatheringPipeline, :start_link,
         [[gathering_id: gathering_id, client_ref: client_ref]]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
end
