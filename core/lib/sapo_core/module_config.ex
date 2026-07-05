defmodule SapoCore.ModuleConfig do
  @moduledoc """
  Boot-time validation of each module's nix-provided config against its
  `config_schema/0` (a NimbleOptions schema). Fails fast with the module
  name on invalid config. Modules with an empty schema accept anything.
  """

  alias SapoCore.Generated.Registry

  @doc "A module's config map by id (backs `SapoKit.ModuleConfig`)."
  @spec fetch(atom()) :: map()
  def fetch(module_id) when is_atom(module_id) do
    Map.get(Registry.module_config(), module_id, %{})
  end

  @doc "Validate every enabled module's config. Returns `:ok` or raises."
  @spec validate!([module()], %{atom() => map()}) :: :ok
  def validate!(modules \\ Registry.modules(), config \\ Registry.module_config()) do
    for mod <- modules do
      case mod.config_schema() do
        [] ->
          :ok

        schema ->
          opts =
            config
            |> Map.get(mod.id(), %{})
            |> Enum.map(fn
              {k, v} when is_atom(k) -> {k, v}
              {k, v} when is_binary(k) -> {String.to_atom(k), v}
            end)

          case NimbleOptions.validate(opts, schema) do
            {:ok, _validated} ->
              :ok

            {:error, %NimbleOptions.ValidationError{} = error} ->
              raise ArgumentError,
                    "invalid config for module #{inspect(mod.id())}: " <>
                      Exception.message(error)
          end
      end
    end

    :ok
  end
end
