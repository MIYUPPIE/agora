defmodule Agora.Posts.Storage do
  @moduledoc """
  Persists a post-media file (already resized/normalized by the caller)
  under `key` and returns its public URL.

  Writes to R2/S3 when `:agora, :uploads_bucket` is configured (prod);
  otherwise falls back to `priv/static/uploads/<key>`, served by
  `Plug.Static` — no cloud credentials needed for local dev.
  """

  require Logger

  @doc "path is a local file path (e.g. from an upload's temp location)."
  def put(path, key, content_type) do
    case Application.get_env(:agora, :uploads_bucket) do
      nil -> put_local(path, key)
      bucket -> put_remote(path, key, content_type, bucket)
    end
  end

  defp put_local(path, key) do
    dest = Path.join(local_dir(), key)
    File.mkdir_p!(Path.dirname(dest))
    File.cp!(path, dest)
    {:ok, "/uploads/#{key}"}
  end

  # Test env points this at a scratch dir (see config/test.exs) so test runs
  # don't leave real files under priv/static/uploads.
  defp local_dir do
    Application.get_env(:agora, :uploads_local_dir) ||
      Path.join([:code.priv_dir(:agora), "static", "uploads"])
  end

  defp put_remote(path, key, content_type, bucket) do
    body = File.read!(path)

    case ExAws.S3.put_object(bucket, key, body, content_type: content_type) |> ExAws.request() do
      {:ok, _} ->
        base = Application.fetch_env!(:agora, :cdn_base_url)
        {:ok, "#{base}/#{key}"}

      {:error, reason} ->
        Logger.error("R2 upload failed for #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
