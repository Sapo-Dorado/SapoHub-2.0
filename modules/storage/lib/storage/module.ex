defmodule Storage.Module do
  @moduledoc """
  SapoKit.Module implementation for Storage — a cross-module file browser
  and manual-upload area, mirroring SapoHub v1's storage page.

  Unlike an ordinary util module, this one is intentionally given
  cross-module visibility (via `SapoKit.Storage.list_all/0`, `.resolve/1`,
  `.delete/1`) rather than being confined to its own storage dir. Storage
  visibility/management is exactly the kind of cross-cutting "more than one
  module needs it" concern the module-authoring guide calls out as core
  service territory — it's just packaged as an ordinary toggleable module
  (rather than baked permanently into core) so it can be enabled/disabled
  like anything else in the hub config.

  It still keeps one private directory of its own (`storage_paths/0`) for
  manually-uploaded files that don't belong to any other module.
  """
  use SapoKit.Module

  @impl true
  def id, do: :storage

  @impl true
  def title, do: "Storage"

  @impl true
  def icon, do: "hero-archive-box"

  @impl true
  def ui_routes do
    [%{path: "/storage", live_view: StorageWeb.Live.Index, action: :index}]
  end

  @impl true
  def api_routes do
    [
      %{
        verb: :post,
        path: "/storage/upload",
        controller: StorageWeb.Api.UploadController,
        action: :create
      }
    ]
  end

  @impl true
  def storage_paths, do: ["uploads"]
end
