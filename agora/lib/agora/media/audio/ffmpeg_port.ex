defmodule Agora.Media.Audio.FFmpegPort do
  @moduledoc """
  Shared Erlang Port lifecycle for the ffmpeg-backed AAC<->PCM codec
  elements (`Agora.Media.Audio.AACDecoder`, `Agora.Media.Audio.AACEncoder`).

  Why ffmpeg via a subprocess Port instead of a native Membrane AAC codec
  plugin: the usual choice, `membrane_aac_fdk_plugin`, wraps libfdk-aac —
  not installed on this host, and not something to `apt install` as a
  side effect of shipping a live-effects feature (it's a proprietary,
  patent-encumbered codec library; pulling it in is a deliberate call for
  Olayemi to make, not an implicit one). ffmpeg, on the other hand, is
  already a hard runtime dependency of this app —
  `Agora.Media.BrowserBroadcastBridge` shells out to it for every
  browser-mic broadcast — and it ships a free, GPL, built-in AAC
  codec (`ffmpeg -encoders`/`-decoders` both list plain `aac`, confirmed
  on this host). Decoding/encoding through a long-running ffmpeg
  subprocess reuses a dependency this app already requires instead of
  adding a new one.
  """

  @spec open([String.t()]) :: port()
  def open(args) do
    executable =
      Application.get_env(:agora, :audio_effects_ffmpeg, "ffmpeg") |> System.find_executable()

    unless executable, do: raise("ffmpeg executable not found on PATH")

    Port.open({:spawn_executable, executable}, [
      :binary,
      :exit_status,
      args: ["-hide_banner", "-loglevel", "error", "-nostats" | args]
    ])
  end

  @spec write(port() | nil, binary()) :: :ok
  def write(nil, _data), do: :ok

  def write(port, data) when is_binary(data) do
    if Port.info(port), do: Port.command(port, data)
    :ok
  end

  @spec close(port() | nil) :: :ok
  def close(nil), do: :ok

  def close(port) do
    if Port.info(port), do: Port.close(port)
    :ok
  end
end
