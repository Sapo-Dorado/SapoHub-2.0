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
      live "/assistant", SapoCoreWeb.AssistantLive, :index

      module_live_routes()
    end
  end

  scope "/api", SapoCoreWeb.Api do
    pipe_through :api

    # Core services
    post "/notify", NotifyController, :create

    get "/notification-destinations", DestinationController, :index
    post "/notification-destinations", DestinationController, :create
    delete "/notification-destinations/:id", DestinationController, :delete
    post "/notification-destinations/:id/set-default", DestinationController, :set_default

    get "/storage/files", StorageController, :index
    get "/storage/files/*path", StorageController, :show
    delete "/storage/files/*path", StorageController, :delete
  end

  scope "/api" do
    pipe_through :api

    module_api_routes()
  end
end
