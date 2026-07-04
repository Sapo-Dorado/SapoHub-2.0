defmodule SapoCoreWeb.ModuleRouter do
  @moduledoc """
  Router macros that expand the enabled modules' declared routes into real
  router entries at compile time.

  Because module apps are dependencies of core, their `SapoKit.Module`
  implementations are already compiled when the router is, so the macros can
  simply execute the callbacks. Routes are real entries (not forwards), so
  `Phoenix.Router.routes/1` introspection — used by the AI context — sees
  them all.
  """

  # Paths owned by core; modules may not claim them.
  @reserved_ui_paths ["/", "/settings", "/assistant"]
  @reserved_api_paths ["/claude-context", "/snapshot"]

  @doc "Reserved core UI paths."
  def reserved_ui_paths, do: @reserved_ui_paths

  @doc "Reserved core API paths."
  def reserved_api_paths, do: @reserved_api_paths

  defmacro module_live_routes do
    routes =
      for mod <- SapoCore.Generated.Registry.modules(), route <- mod.ui_routes() do
        {mod, route}
      end

    check_ui_routes!(routes)

    for {_mod, route} <- routes do
      action = Map.get(route, :action, :index)

      quote do
        live unquote(route.path), unquote(route.live_view), unquote(action)
      end
    end
  end

  defmacro module_api_routes do
    routes =
      for mod <- SapoCore.Generated.Registry.modules(), route <- mod.api_routes() do
        {mod, route}
      end

    check_api_routes!(routes)

    for {_mod, route} <- routes do
      verb = route.verb

      unless verb in [:get, :post, :patch, :put, :delete] do
        raise ArgumentError, "unsupported API verb #{inspect(verb)} in #{inspect(route)}"
      end

      quote do
        unquote(verb)(unquote(route.path), unquote(route.controller), unquote(route.action))
      end
    end
  end

  @doc "Validates module UI routes: no reserved paths, no cross-module duplicates. Raises on violation."
  def check_ui_routes!(routes), do: check_collisions!(routes, @reserved_ui_paths, "UI")

  defp check_collisions!(routes, reserved, kind) do
    routes
    |> Enum.group_by(fn {_mod, route} -> route.path end)
    |> Enum.each(fn {path, entries} ->
      if path in reserved do
        [{mod, _} | _] = entries

        raise CompileError,
          description:
            "#{kind} route #{inspect(path)} declared by #{inspect(mod)} is reserved by SapoHub core"
      end

      case Enum.uniq_by(entries, fn {mod, _} -> mod end) do
        [_] ->
          :ok

        many ->
          mods = Enum.map(many, fn {mod, _} -> inspect(mod) end) |> Enum.join(", ")

          raise CompileError,
            description: "#{kind} route #{inspect(path)} declared by multiple modules: #{mods}"
      end
    end)
  end

  @doc "Validates module API routes: no reserved paths, no cross-module duplicates. Raises on violation."
  def check_api_routes!(routes) do
    reserved = @reserved_api_paths

    routes
    |> Enum.group_by(fn {_mod, route} -> {route.verb, route.path} end)
    |> Enum.each(fn {{verb, path}, entries} ->
      if path in reserved do
        [{mod, _} | _] = entries

        raise CompileError,
          description:
            "API route #{inspect(path)} declared by #{inspect(mod)} is reserved by SapoHub core"
      end

      case Enum.uniq_by(entries, fn {mod, _} -> mod end) do
        [_] ->
          :ok

        many ->
          mods = Enum.map(many, fn {mod, _} -> inspect(mod) end) |> Enum.join(", ")

          raise CompileError,
            description:
              "API route #{verb} #{inspect(path)} declared by multiple modules: #{mods}"
      end
    end)
  end
end
