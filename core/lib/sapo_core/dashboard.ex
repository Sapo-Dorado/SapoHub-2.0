defmodule SapoCore.Dashboard do
  @moduledoc """
  The dashboard slot list: one entry per enabled module, using whichever
  `dashboard_buttons/1` option the user picked (see `dashboard_button.<id>`
  in `SapoCore.Prefs`). The assistant is NOT a slot — it's the floating
  button rendered in the root layout on every page (see
  `root.html.heex` + the `FloatingAssistant` JS hook), same as SapoHub v1.

  Slot CONTENT (which modules exist, which button variant each shows) is
  fixed at build time / by the `dashboard_button.<id>` pref. Slot ORDER is
  separate and lives entirely in prefs (`"dashboard_order"`, a
  comma-separated list of slot ids) so it can be changed from Settings
  without a redeploy, same as everything else in `SapoCore.Prefs`. Unset
  or unrecognized ids fall back to natural order: Nix module order (see
  `SapoCore.Generated.Registry`).

  Shared by `DashboardLive` (renders the ordered list) and `SettingsLive`
  (lets the user reorder it).
  """

  alias SapoCore.Generated.Registry

  @doc "Slots in natural order (Nix module order) — ignores the reorder pref."
  def base_slots do
    module_slots()
  end

  @doc "Slots in the user's configured order (`dashboard_order` pref, falling back to natural order)."
  def ordered_slots do
    ids = order_ids()

    Enum.sort_by(base_slots(), fn slot ->
      Enum.find_index(ids, &(&1 == to_string(slot.id))) || length(ids)
    end)
  end

  @doc "Persist a new order. `ids` may be any mix of atoms/strings; stringified before saving."
  def save_order(ids) do
    SapoCore.Prefs.put("dashboard_order", Enum.map_join(ids, ",", &to_string/1))
  end

  defp order_ids do
    SapoCore.Prefs.get("dashboard_order", "")
    |> String.split(",", trim: true)
  end

  defp module_slots do
    for mod <- Registry.modules(), path = first_path(mod), not is_nil(path) do
      config = Registry.config_for(mod)
      variant = SapoCore.Prefs.get("dashboard_button.#{mod.id()}", "default")

      button =
        Enum.find_value(mod.dashboard_buttons(config), fn button ->
          if button.id == variant, do: button
        end)

      %{
        id: mod.id(),
        title: String.downcase(mod.title()),
        icon: mod.icon(),
        path: path,
        component: button && button.component,
        size: (button && button.size) || :standard
      }
    end
  end

  defp first_path(mod) do
    case mod.ui_routes() do
      [%{path: path} | _] -> path
      [] -> nil
    end
  end
end
