defmodule SapoKit.Web do
  @moduledoc """
  Web helpers for util modules.

  Modules cannot `use SapoCoreWeb` (that would create a dependency cycle),
  so they use this instead:

      use SapoKit.Web, :live_view     # LiveView pages
      use SapoKit.Web, :controller    # JSON API controllers
      use SapoKit.Web, :html          # function components

  LiveViews should wrap their content in the host layout:

      <SapoKit.Layouts.app flash={@flash}>
        ...
      </SapoKit.Layouts.app>
  """

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn
      import SapoKit.Web.ApiHelpers
    end
  end

  def html do
    quote do
      use Phoenix.Component

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML

      alias Phoenix.LiveView.JS
      alias SapoKit.Layouts
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
