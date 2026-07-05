defmodule SapoKit.ModuleConfig do
  @moduledoc """
  Runtime access to a module's own (validated) config, for code paths that
  don't receive it as an argument (contexts, hooks):

      remind_time = SapoKit.ModuleConfig.get(:my_plate)[:default_remind_time]

  Keys may be atoms or strings depending on the config source (dev registry
  vs nix-serialized); `get/2` checks both.
  """

  @spec get(atom()) :: map()
  def get(module_id) when is_atom(module_id), do: impl().fetch(module_id)

  @spec get(atom(), atom()) :: term()
  def get(module_id, key) when is_atom(module_id) and is_atom(key) do
    config = get(module_id)
    Map.get(config, key) || Map.get(config, to_string(key))
  end

  defp impl, do: Application.fetch_env!(:sapo_module_kit, :module_config)
end
