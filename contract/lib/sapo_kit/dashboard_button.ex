defmodule SapoKit.DashboardButton do
  @moduledoc """
  A dashboard button OPTION a module offers for its dashboard slot (see
  `c:SapoKit.Module.dashboard_buttons/1`).

  Every module gets a "default" option for free: icon + title, navigating
  to its first UI route. Entries here are ADDITIONAL options — each one a
  fully custom `Phoenix.LiveComponent` that owns the whole tile. A module
  can offer more than one (e.g. a compact view and a fuller one); the
  user picks per utility in Settings.

  There is deliberately no separate "icon + title + one line of status
  text" shape. That in-between pattern used to exist and it pushed every
  module toward the same shallow result — a lone count squeezed onto the
  tile. If what you want is a short status string, add a
  `SapoKit.StatuslineItem` instead (see
  `c:SapoKit.Module.statusline_items/1`) — it's visible everywhere, in
  the top bar, without spending dashboard space. Reach for a dashboard
  button option only when there's real content to lay out: a short list,
  a handful of structured stats, secondary actions.

      %SapoKit.DashboardButton{
        id: "preview",
        label: "task preview — urgent tasks",
        component: MyPlateWeb.TaskPreview,
        size: :wide
      }

  The component receives `id` and `module_id` assigns and is rendered
  INSIDE the slot; the parent re-renders it (via a `refresh` assign)
  whenever the module's PubSub topics fire.

  `:size` controls how much grid room the slot gets — independent of
  whether the option is the module's only one or one of several; pick
  whatever room THIS option's content needs, per option:

  * `:standard` (default) - the normal single-column slot.
  * `:wide` - takes 2 of the grid's 3 columns; the grid then packs a
    standard tile in beside it. Use this when an option has more to show
    than a standard slot's icon-and-title fits — a task list, a small
    chart, anything with real rows.
  * `:extra_wide` - takes all 3 columns; nothing else shares its row.
    Use this rarely, for a component with enough content that even the
    2-column `:wide` slot would cramp it.
  """

  @enforce_keys [:id, :label, :component]
  defstruct [:id, :label, :component, size: :standard]

  @type size :: :standard | :wide | :extra_wide

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          component: module(),
          size: size()
        }

  @doc "The list of supported button sizes."
  def sizes, do: [:standard, :wide, :extra_wide]
end
