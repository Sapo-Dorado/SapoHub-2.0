defmodule SapoCore.StatuslineTest do
  use ExUnit.Case, async: false

  alias SapoCore.Prefs
  alias SapoCore.Statusline

  setup do
    on_exit(fn -> File.rm(Application.fetch_env!(:sapo_core, :prefs_overlay)) end)
    :ok
  end

  test "unset statusline_order falls back to natural order, filtered by per-item toggle" do
    ids = Statusline.enabled_items() |> Enum.map(& &1.id)
    assert ids == Statusline.all_items() |> Enum.map(& &1.id)

    :ok = Prefs.put("statusline.core.snapshot", false)
    ids = Statusline.enabled_items() |> Enum.map(& &1.id)
    refute "core.snapshot" in ids
  end

  test "statusline_order selects and orders explicitly, ignoring per-item toggles" do
    :ok = Prefs.put("statusline.my_plate.due", false)

    Statusline.save_order(["my_plate.due", "core.scheduler"])

    assert Statusline.enabled_items() |> Enum.map(& &1.id) ==
             ["my_plate.due", "core.scheduler"]
  end

  test "statusline_order silently drops unknown ids" do
    Statusline.save_order(["core.scheduler", "nonexistent.item"])

    assert Statusline.enabled_items() |> Enum.map(& &1.id) == ["core.scheduler"]
  end

  test "save_order accepts atoms or strings" do
    Statusline.save_order([:"core.scheduler"])
    assert Statusline.enabled_items() |> Enum.map(& &1.id) == ["core.scheduler"]
  end
end
