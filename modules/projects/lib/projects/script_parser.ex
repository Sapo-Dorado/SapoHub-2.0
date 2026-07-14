defmodule Projects.ScriptParser do
  @moduledoc """
  Discovers and parses `SAPO_SCRIPT_*` headers out of `source/scripts/*.sh`.
  Ported verbatim from v1's `ScriptParser`.
  """

  alias Projects.Disk

  @doc """
  Returns a list of parsed scripts for a project name.
  Each entry: `%{name:, file:, params:, optional_params:, sudo:, sync:}`.
  Scripts without a `SAPO_SCRIPT_NAME` header are skipped.
  """
  def parse_scripts(project_name) do
    scripts_dir = Path.join(Disk.source_path(project_name), "scripts")

    case File.ls(scripts_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".sh"))
        |> Enum.map(&Path.join(scripts_dir, &1))
        |> Enum.map(&parse_script/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.name)

      {:error, _} ->
        []
    end
  end

  defp parse_script(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        lines = String.split(content, "\n")
        name = extract_header(lines, "SAPO_SCRIPT_NAME")

        if name do
          params = extract_all_headers(lines, "SAPO_SCRIPT_PARAM")
          optional_params = extract_all_headers(lines, "SAPO_SCRIPT_PARAM_OPTIONAL")
          sudo = extract_header(lines, "SAPO_SCRIPT_SUDO") == "true"
          sync = extract_header(lines, "SAPO_SCRIPT_SYNC") == "true"

          %{
            name: name,
            file: file_path,
            params: params,
            optional_params: optional_params,
            sudo: sudo,
            sync: sync
          }
        end

      {:error, _} ->
        nil
    end
  end

  defp extract_header(lines, key) do
    prefix = "# #{key}: "

    Enum.find_value(lines, fn line ->
      if String.starts_with?(line, prefix) do
        String.trim(String.replace_prefix(line, prefix, ""))
      end
    end)
  end

  defp extract_all_headers(lines, key) do
    prefix = "# #{key}: "

    lines
    |> Enum.filter(&String.starts_with?(&1, prefix))
    |> Enum.map(&String.trim(String.replace_prefix(&1, prefix, "")))
  end
end
