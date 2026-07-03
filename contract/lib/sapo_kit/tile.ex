defmodule SapoKit.Tile do
  @moduledoc """
  Describes a module's button/tile on the SapoHub dashboard.

  * `:label` - text shown on the tile
  * `:icon` - heroicon name (e.g. `"hero-clipboard-document-list"`)
  * `:path` - where the tile navigates to (usually the module's LiveView route)
  * `:style` - one of `:standard`, `:wide` or `:accent`
  * `:badge` - optional zero-arity fun returning a short string (e.g. a count)
    displayed on the tile. Executed asynchronously after dashboard mount so a
    slow badge can never block page load. Return `nil` to show no badge.
  """

  @enforce_keys [:label, :path]
  defstruct [:label, :path, :badge, icon: "hero-squares-2x2", style: :standard]

  @type style :: :standard | :wide | :accent

  @type t :: %__MODULE__{
          label: String.t(),
          icon: String.t(),
          path: String.t(),
          style: style(),
          badge: (-> String.t() | nil) | nil
        }

  @styles [:standard, :wide, :accent]
  @doc "The list of supported tile styles."
  def styles, do: @styles
end
