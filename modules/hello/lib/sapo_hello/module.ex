defmodule SapoHello.Module do
  @moduledoc """
  The `SapoKit.Module` implementation for the hello reference module.

  This file is the canonical example of the module contract — every callback
  a real module might override is exercised somewhere in this module's
  source tree.
  """
  use SapoKit.Module

  @impl true
  def id, do: :sapo_hello

  @impl true
  def title, do: "Hello"

  @impl true
  def dashboard_tile(config) do
    %SapoKit.Tile{
      label: "Hello",
      icon: "hero-hand-raised",
      path: "/hello",
      style: config[:tile_style] || :standard,
      badge: fn -> to_string(SapoHello.count_greetings()) end
    }
  end

  @impl true
  def ui_routes do
    [%{path: "/hello", live_view: SapoHelloWeb.Live.Index, action: :index}]
  end

  @impl true
  def api_routes do
    [
      %{verb: :get, path: "/hello", controller: SapoHelloWeb.Api.GreetingsController, action: :index},
      %{verb: :post, path: "/hello", controller: SapoHelloWeb.Api.GreetingsController, action: :create},
      %{verb: :delete, path: "/hello/:id", controller: SapoHelloWeb.Api.GreetingsController, action: :delete}
    ]
  end

  @impl true
  def icon, do: "hero-hand-raised"

  @impl true
  def settings_component, do: SapoHelloWeb.SettingsComponent

  # Storage is opt-in: returning a non-empty list gives this module a
  # dedicated directory (["."] = just the directory, no subdirs).
  @impl true
  def storage_paths, do: ["."]

  @impl true
  def ai_context do
    """
    Hello is a reference module for testing. Greetings: #{SapoHello.count_greetings()}.
    Use `sapo hello list|create|delete` or the /api/hello endpoints.
    """
  end

  @impl true
  def config_schema do
    [tile_style: [type: {:in, [:standard, :wide, :accent]}, default: :standard]]
  end
end
