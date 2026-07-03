defmodule SapoCoreWeb.Router do
  use SapoCoreWeb, :router
  import SapoCoreWeb.ModuleRouter

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SapoCoreWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # No auth on the API: SapoHub is only reachable over Tailscale.
  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/" do
    pipe_through :browser

    # A single live_session so navigation between core pages and module
    # pages reuses one LiveView websocket (required for <.link navigate>).
    live_session :default do
      live "/", SapoCoreWeb.DashboardLive, :index

      module_live_routes()
    end
  end

  scope "/api" do
    pipe_through :api

    module_api_routes()
  end
end
