defmodule SapoKit.Layouts do
  @moduledoc """
  Layout facade for util modules.

  Delegates to the host application's layouts module so module LiveViews can
  render inside the shared app chrome without depending on core:

      config :sapo_module_kit, layouts: SapoCoreWeb.Layouts
  """

  use Phoenix.Component

  attr :flash, :map, required: true
  slot :inner_block, required: true

  def app(assigns) do
    layouts = Application.fetch_env!(:sapo_module_kit, :layouts)
    layouts.app(assigns)
  end
end
