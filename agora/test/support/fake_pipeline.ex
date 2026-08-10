defmodule FakePipeline do
  @moduledoc """
  Stands in for a running `Agora.Media.GatheringPipeline` in tests that
  only need to prove `Agora.Media.AudioEffects` correctly finds and
  calls the live pipeline via `Agora.Media.GatheringRegistry` +
  `Membrane.Pipeline.call/2` — without paying for a real Membrane
  pipeline (RTMP client, ffmpeg subprocesses, HLS packaging) that has
  nothing to do with what's under test.

  `Membrane.Pipeline.call/2` is just `GenServer.call/3` under the hood,
  so a plain GenServer registered under the same registry key
  round-trips through the exact same code path a real pipeline would.
  """

  use GenServer

  def start_link(opts) do
    gathering_id = Keyword.fetch!(opts, :gathering_id)
    test_pid = Keyword.fetch!(opts, :test_pid)

    GenServer.start_link(__MODULE__, %{test_pid: test_pid},
      name: {:via, Registry, {Agora.Media.GatheringRegistry, gathering_id}}
    )
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(message, _from, %{test_pid: test_pid} = state) do
    send(test_pid, {:got_call, message})
    {:reply, :ok, state}
  end
end
