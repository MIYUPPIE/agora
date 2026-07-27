defmodule Agora.Posts.ImageProcessor do
  @moduledoc """
  Resizes an uploaded image to a sane max width before it's stored —
  phones produce multi-megabyte photos that don't need to ship at full
  resolution to a feed thumbnail or even a detail view.
  """

  @max_width 1600

  @doc """
  Resizes `src_path` down to `@max_width` (no upscaling) and writes the
  result to a new temp file. Returns `{:ok, path, byte_size}`.
  """
  def process(src_path) do
    with {:ok, image} <- Image.open(src_path),
         {:ok, resized} <- Image.thumbnail(image, @max_width) do
      dest =
        Path.join(System.tmp_dir!(), "agora_upload_#{System.unique_integer([:positive])}.jpg")

      case Image.write(resized, dest, quality: 85) do
        {:ok, _} ->
          {:ok, dest, File.stat!(dest).size}

        error ->
          error
      end
    end
  end
end
