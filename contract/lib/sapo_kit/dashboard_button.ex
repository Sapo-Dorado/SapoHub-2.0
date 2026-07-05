defmodule SapoKit.DashboardButton do
  @moduledoc """
  A dashboard button OPTION a module offers for its fixed-size dashboard
  slot (see `c:SapoKit.Module.dashboard_buttons/1`).

  Every module gets a "default" button for free (icon + title, navigating
  to its first UI route). Entries here are additional variants — usually a
  status button rendered by a LiveComponent:

      %SapoKit.DashboardButton{
        id: "status",
        label: "status — active & due counts",
        component: MyPlateWeb.StatusButton
      }

  The component is a `Phoenix.LiveComponent` rendered INSIDE the slot; it
  receives `id` and `module_id` assigns and must fit the standard slot
  size. The user picks which variant each utility uses (Settings →
  Dashboard buttons).
  """

  @enforce_keys [:id, :label, :component]
  defstruct [:id, :label, :component]

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          component: module()
        }
end
