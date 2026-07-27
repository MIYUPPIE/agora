defmodule Agora.Media.Storage do
  @moduledoc """
  Persists gathering-derived audio (listener recordings, full-gathering
  replay archives) and returns its public URL.

  Writes to R2/S3 when `:agora, :recordings_bucket` is configured
  (prod); otherwise falls back to local disk under the same
  `media_root` tree that live segments use, served by the existing
  `/media` static mount — no cloud credentials needed for local dev.
  """

  require Logger

  def put(path, key, content_type) do
    case Application.get_env(:agora, :recordings_bucket) do
      nil -> put_local(path, key)
      bucket -> put_remote(path, key, content_type, bucket)
    end
  end

  defp put_local(path, key) do
    dest = Path.join(Application.fetch_env!(:agora, :media_root), key)
    File.mkdir_p!(Path.dirname(dest))
    File.cp!(path, dest)
    {:ok, "/media/#{key}"}
  end

  defp put_remote(path, key, content_type, bucket) do
    body = File.read!(path)
    disposition = ~s(attachment; filename="agora#{Path.extname(key)}")

    case ExAws.S3.put_object(bucket, key, body,
           content_type: content_type,
           content_disposition: disposition
         )
         |> ExAws.request() do
      {:ok, _} ->
        base = Application.fetch_env!(:agora, :cdn_base_url)
        {:ok, "#{base}/#{key}"}

      {:error, reason} ->
        Logger.error("R2 recordings upload failed for #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
