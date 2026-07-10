defmodule Storage do
  @moduledoc """
  Context for the Storage module: cross-module file visibility + manual
  uploads, via `SapoKit.Storage`.
  """

  alias SapoKit.Storage, as: Facade

  @doc "All files across every module that has opted into storage, sorted by path."
  @spec list_files() :: [%{path: String.t(), size: non_neg_integer(), mtime: DateTime.t()}]
  def list_files, do: Facade.list_all()

  @doc "Delete a file at an API path (`<module_id>/<relative path>`), across any opted-in module."
  @spec delete_file(String.t()) :: :ok | {:error, term()}
  def delete_file(api_path), do: Facade.delete(api_path)

  @doc """
  Save an uploaded file into this module's own `uploads/` storage dir.
  Returns the API path (`storage/uploads/<name>`) it was saved under,
  disambiguating the filename if one already exists.
  """
  @spec save_upload(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def save_upload(tmp_path, filename) do
    dest_dir = Facade.path(:storage, "uploads")
    File.mkdir_p!(dest_dir)

    safe_name = Path.basename(filename)
    dest = unique_path(dest_dir, safe_name)

    case File.cp(tmp_path, dest) do
      :ok -> {:ok, "storage/uploads/" <> Path.basename(dest)}
      error -> error
    end
  end

  defp unique_path(dir, filename) do
    candidate = Path.join(dir, filename)

    if File.exists?(candidate) do
      ext = Path.extname(filename)
      base = Path.basename(filename, ext)
      unique_path(dir, "#{base}-#{System.unique_integer([:positive, :monotonic])}#{ext}")
    else
      candidate
    end
  end
end
