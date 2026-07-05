defmodule SapoKit.StatuslineItem do
  @moduledoc """
  A segment a module offers for the global statusline
  (see `c:SapoKit.Module.statusline_items/1`).

      %SapoKit.StatuslineItem{
        id: "my_plate.due",
        label: "Tasks due",
        text: fn -> "\#{MyPlate.count_due_today()} due" end,
        level: fn -> if MyPlate.count_due_today() > 0, do: :warn, else: :ok end,
        topics: ["my_plate:tasks"]
      }

  Rendering rules (core-owned): mono font; `level` tints the text —
  `:ok` moss, `:warn` amber, `:neutral` muted. `text` and `level` run with
  a rescue guard so a broken module cannot take the bar down; items
  re-evaluate when any of `topics` broadcasts on `SapoKit.PubSub` and on a
  periodic refresh tick. The user toggles items in Settings.
  """

  @enforce_keys [:id, :label, :text]
  defstruct [:id, :label, :text, level: :neutral, topics: []]

  @type level :: :ok | :warn | :neutral

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          text: (-> String.t()),
          level: level() | (-> level()),
          topics: [String.t()]
        }
end
