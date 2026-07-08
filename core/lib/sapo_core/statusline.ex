defmodule SapoCore.Statusline do
  @moduledoc """
  Collects and evaluates statusline items: core items (scheduler,
  snapshot age) plus every enabled module's `statusline_items/1`.

  Which items show, and in what order, is controlled by the
  `"statusline_order"` pref — a comma-separated list of item ids, front
  to back. When set, it's the definitive list: only those ids show, in
  that order (any per-item `statusline.<id>` toggle is ignored). When
  unset (the default), falls back to natural order (core items first,
  then per-module, in Nix module order), filtered by each item's own
  `statusline.<id>` toggle (default enabled) — the original behavior.

  Evaluation is rescue-guarded so a broken item renders as `--` instead of
  taking the bar down.
  """

  alias SapoCore.Generated.Registry
  alias SapoKit.StatuslineItem

  @doc "All offered items (for the Settings toggles), natural order."
  def all_items do
    core_items() ++
      for mod <- Registry.modules(),
          item <- safe_items(mod),
          do: item
  end

  @doc """
  Items to actually show, in the configured order. See the moduledoc for
  the `"statusline_order"` pref / per-item toggle fallback rules.
  """
  def enabled_items do
    case order_ids() do
      [] -> Enum.filter(all_items(), &SapoCore.Prefs.get("statusline.#{&1.id}", true))
      ids -> select_ordered(all_items(), ids)
    end
  end

  @doc "Persist an explicit order/selection. `ids` may be any mix of atoms/strings."
  def save_order(ids) do
    SapoCore.Prefs.put("statusline_order", Enum.map_join(ids, ",", &to_string/1))
  end

  @doc "All PubSub topics the enabled items listen on."
  def topics do
    enabled_items() |> Enum.flat_map(& &1.topics) |> Enum.uniq()
  end

  @doc "Evaluate items to render structs: `%{id, text, level}`."
  def evaluate(items \\ enabled_items()) do
    for item <- items do
      %{id: item.id, text: safe_text(item), level: safe_level(item)}
    end
  end

  defp select_ordered(items, ids) do
    by_id = Map.new(items, &{&1.id, &1})
    for id <- ids, item = Map.get(by_id, id), not is_nil(item), do: item
  end

  defp order_ids do
    SapoCore.Prefs.get("statusline_order", "")
    |> String.split(",", trim: true)
  end

  defp core_items do
    [
      %StatuslineItem{
        id: "core.scheduler",
        label: "Scheduler",
        text: fn ->
          if Process.whereis(SapoCore.Scheduler), do: "scheduler ✓", else: "scheduler ✗"
        end,
        level: fn ->
          if Process.whereis(SapoCore.Scheduler), do: :ok, else: :warn
        end
      },
      %StatuslineItem{
        id: "core.snapshot",
        label: "Snapshot age",
        text: fn ->
          case SapoCore.Snapshot.list() do
            [%{mtime: mtime} | _] -> "snapshot #{age(mtime)}"
            [] -> "snapshot none"
          end
        end,
        level: fn ->
          case SapoCore.Snapshot.list() do
            [%{mtime: mtime} | _] ->
              if DateTime.diff(DateTime.utc_now(), mtime, :day) >= 7, do: :warn, else: :ok

            [] ->
              :warn
          end
        end
      }
    ]
  end

  defp age(mtime) do
    diff = DateTime.diff(DateTime.utc_now(), mtime, :second)

    cond do
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp safe_items(mod) do
    mod.statusline_items(Registry.config_for(mod))
  rescue
    _ -> []
  end

  defp safe_text(%StatuslineItem{text: fun}) when is_function(fun, 0) do
    fun.()
  rescue
    _ -> "--"
  end

  defp safe_level(%StatuslineItem{level: level}) when level in [:ok, :warn, :neutral], do: level

  defp safe_level(%StatuslineItem{level: fun}) when is_function(fun, 0) do
    case fun.() do
      level when level in [:ok, :warn, :neutral] -> level
      _ -> :neutral
    end
  rescue
    _ -> :neutral
  end
end
