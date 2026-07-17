defmodule Storage do
  @moduledoc """
  Context for the Storage module: a plain, uniform folder-tree browser +
  manager over every module's storage, via `SapoKit.Storage`. Every
  opted-in module's storage is just files and folders relative to the
  storage root — there is no special treatment per module, only the
  guarantee (enforced at the core level) that modules' storage dirs don't
  overlap.
  """

  alias SapoKit.Storage, as: Facade

  @doc "All files across every module that has opted into storage, sorted by path."
  @spec list_files() :: [%{path: String.t(), size: non_neg_integer(), mtime: DateTime.t()}]
  def list_files, do: Facade.list_all()

  @doc """
  List the immediate contents (subfolders + files) at an API path relative
  to the storage root. `[]` lists the top level.
  """
  @spec list_dir([String.t()]) ::
          {:ok, %{dirs: [map()], files: [map()]}} | {:error, :invalid_path}
  def list_dir(path_segments), do: Facade.list_dir(Enum.join(path_segments, "/"))

  @doc "Create a folder at an API path (path segments) relative to the storage root."
  @spec create_folder([String.t()]) :: :ok | {:error, term()}
  def create_folder(path_segments), do: Facade.mkdir(Enum.join(path_segments, "/"))

  @doc "Delete a file or folder at an API path (`<module_id>/<relative path>`), across any opted-in module."
  @spec delete_file(String.t()) :: :ok | {:error, term()}
  def delete_file(api_path), do: Facade.delete(api_path)

  @max_preview_bytes 1_000_000

  @doc """
  Read a text/code/markdown file for inline preview. Capped at
  #{@max_preview_bytes} bytes so a stray large file can't be pulled fully
  into LiveView memory — callers should send people over the existing
  download link for anything bigger.
  """
  @spec read_text(String.t()) :: {:ok, String.t()} | {:error, :too_large | term()}
  def read_text(api_path) do
    with {:ok, abs} <- Facade.resolve(api_path),
         {:ok, %File.Stat{size: size}} <- File.stat(abs) do
      if size > @max_preview_bytes do
        {:error, :too_large}
      else
        File.read(abs)
      end
    end
  end

  @doc """
  Save an uploaded file into the given folder (path segments, relative to
  the storage root — e.g. `["storage", "uploads"]`). Returns the API path
  it was saved under, disambiguating the filename if one already exists.
  """
  @spec save_upload(String.t(), String.t(), [String.t()]) ::
          {:ok, String.t()} | {:error, term()}
  def save_upload(tmp_path, filename, dest_segments) do
    case Facade.resolve_dir(Enum.join(dest_segments, "/")) do
      {:ok, dest_dir} ->
        File.mkdir_p!(dest_dir)

        safe_name = Path.basename(filename)
        dest = unique_path(dest_dir, safe_name)

        case File.cp(tmp_path, dest) do
          :ok -> {:ok, Enum.join(dest_segments ++ [Path.basename(dest)], "/")}
          error -> error
        end

      error ->
        error
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
