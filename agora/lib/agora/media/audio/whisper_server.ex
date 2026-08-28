defmodule Agora.Media.Audio.WhisperServer do
  @moduledoc """
  Supervises one long-running `whisper-server` subprocess (whisper.cpp's
  own HTTP inference server, `examples/server` — see
  `scripts/setup_whisper.sh`), started once at application boot and
  reused by every live Gathering's `Agora.Media.Audio.Transcriber`.

  Why one shared long-lived server instead of shelling out to
  `whisper-cli` per utterance (the way `Agora.Media.Audio.WhisperCli`
  does for the one-shot archival pass): loading a Whisper model is the
  expensive part — confirmed hands-on, a base.en model takes real
  wall-clock time to load into memory. Paying that cost once at boot and
  then hitting a warm HTTP endpoint per utterance is the only way live
  captioning stays low-latency; re-loading the model on every ~1-15s
  utterance (`Agora.Media.Audio.UtteranceBuffer`'s flush cadence) would
  make live captions arrive slower than the utterances that caused them.

  Entirely optional and self-disabling, same stance as ffmpeg's
  libfdk-aac tradeoff in `Agora.Media.Audio.FFmpegPort`: if
  `:whisper_server_bin`/`:whisper_live_model` aren't configured, don't
  point at real files, or the subprocess fails to come up within the
  readiness timeout, this logs once and `available?/0` stays `false`
  forever after — every caller (`Transcriber`) checks that and simply
  skips transcription rather than crashing the broadcast. Live audio
  beats no live audio; this applies the same call to captions.

  ## Shutdown

  `Port.close/1` alone does **not** kill this particular subprocess —
  confirmed the hard way, by orphaning several during development.
  `Agora.Media.Audio.AACDecoder`/`AACEncoder` get away with just closing
  their ffmpeg ports because ffmpeg is a *streaming filter*: closing its
  stdin sends EOF, and ffmpeg exits on EOF by design. `whisper-server` is
  an HTTP daemon that never reads stdin at all — closing an fd it never
  looks at does nothing, and the OS process keeps right on serving,
  invisibly detached from the BEAM, holding the configured port forever.
  `terminate/2` and the failed-readiness branch of `handle_info(:boot,
  ...)` both explicitly `kill -TERM` the child's OS pid (via
  `Port.info/2`) for exactly this reason — `Port.close/1` alone is
  necessary (releases the Erlang-side fd) but not sufficient.
  """

  use GenServer
  require Logger

  @readiness_timeout_ms 20_000
  @readiness_poll_ms 200

  defstruct port: nil, base_url: nil, available: false

  @type t :: %__MODULE__{}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Base URL of the running whisper-server (e.g. \"http://127.0.0.1:8090\"), or `nil` if unavailable."
  @spec base_url() :: String.t() | nil
  def base_url, do: GenServer.call(__MODULE__, :base_url)

  @doc "Whether whisper-server booted successfully and is ready to accept `/inference` requests."
  @spec available?() :: boolean()
  def available?, do: GenServer.call(__MODULE__, :available?)

  @impl true
  def init(_opts) do
    bin = Application.get_env(:agora, :whisper_server_bin)
    model = Application.get_env(:agora, :whisper_live_model)
    port_number = Application.get_env(:agora, :whisper_server_port, 8090)
    base_url = "http://127.0.0.1:#{port_number}"

    cond do
      is_nil(bin) or is_nil(model) ->
        {:ok, %__MODULE__{}}

      not executable?(bin) ->
        Logger.warning(
          "Agora.Media.Audio.WhisperServer: whisper-server binary not found at #{inspect(bin)} " <>
            "(run scripts/setup_whisper.sh) — live transcription disabled."
        )

        {:ok, %__MODULE__{}}

      not File.exists?(model) ->
        Logger.warning(
          "Agora.Media.Audio.WhisperServer: model not found at #{inspect(model)} " <>
            "(run scripts/setup_whisper.sh) — live transcription disabled."
        )

        {:ok, %__MODULE__{}}

      true ->
        send(self(), :boot)
        {:ok, %__MODULE__{base_url: base_url}}
    end
  end

  @impl true
  def handle_info(:boot, state) do
    bin = Application.get_env(:agora, :whisper_server_bin)
    model = Application.get_env(:agora, :whisper_live_model)
    port_number = Application.get_env(:agora, :whisper_server_port, 8090)
    threads = System.schedulers_online() |> min(8) |> Integer.to_string()

    port =
      Port.open({:spawn_executable, bin}, [
        :binary,
        :exit_status,
        args: [
          "-m",
          model,
          "--host",
          "127.0.0.1",
          "--port",
          Integer.to_string(port_number),
          "-t",
          threads
        ]
      ])

    if wait_ready(state.base_url) == :ok do
      Logger.info("Agora.Media.Audio.WhisperServer: ready at #{state.base_url}")
      {:noreply, %{state | port: port, available: true}}
    else
      Logger.error(
        "Agora.Media.Audio.WhisperServer: whisper-server didn't become ready within " <>
          "#{@readiness_timeout_ms}ms — live transcription disabled."
      )

      kill(port)
      {:noreply, %{state | port: nil, available: false}}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error(
      "Agora.Media.Audio.WhisperServer: whisper-server exited with status #{status} — " <>
        "live transcription disabled until the app restarts."
    )

    {:noreply, %{state | port: nil, available: false}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def handle_call(:base_url, _from, state),
    do: {:reply, if(state.available, do: state.base_url), state}

  def handle_call(:available?, _from, state), do: {:reply, state.available, state}

  @impl true
  def terminate(_reason, state) do
    if state.port, do: kill(state.port)
    :ok
  end

  # See the moduledoc's "Shutdown" section — Port.close/1 alone leaves
  # this specific subprocess running as an orphan.
  defp kill(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} -> System.cmd("kill", ["-TERM", Integer.to_string(os_pid)])
      nil -> :ok
    end

    Port.close(port)
  catch
    # Port.info/2 and Port.close/1 both raise ArgumentError for an
    # already-dead port (e.g. the subprocess crashed on its own between
    # the readiness check and this call) — nothing left to kill.
    :error, _ -> :ok
  end

  defp executable?(path), do: File.exists?(path) || System.find_executable(path) != nil

  defp wait_ready(base_url, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + @readiness_timeout_ms
    %URI{host: host, port: port} = URI.parse(base_url)

    case :gen_tcp.connect(String.to_charlist(host), port, [], 300) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, _reason} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(@readiness_poll_ms)
          wait_ready(base_url, deadline)
        else
          :error
        end
    end
  end
end
