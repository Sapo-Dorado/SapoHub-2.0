defmodule SapoKit.Module do
  @moduledoc """
  The behaviour every SapoHub util module implements.

  A util module is a standalone mix project depending only on
  `:sapo_module_kit`. It declares everything SapoHub core needs to integrate
  it: UI routes and a dashboard tile, API routes, migrations, scheduler hooks,
  supervision children, storage paths, required secrets, an AI-context
  fragment and a config schema.

  Util modules are COMPLETELY INDEPENDENT of each other: they never call
  other modules and never expose APIs to them. Anything more than one module
  needs (notifications, storage, scheduling, ...) is core functionality,
  reached through the `SapoKit.*` facades.

  Use it like:

      defmodule MyPlate.Module do
        use SapoKit.Module

        def id, do: :my_plate
        def title, do: "MyPlate"
        # ...override only what you need; everything except id/title has
        # a sensible default.
      end

  The enabled set of modules is composed by Nix into
  `SapoCore.Generated.Registry`; core consumes the callbacks at compile time
  (routes) and at boot (children, storage, secrets, config validation).
  """

  alias SapoKit.Tile

  @typedoc "A LiveView route contributed to the shared `live_session`."
  @type ui_route :: %{
          required(:path) => String.t(),
          required(:live_view) => module(),
          optional(:action) => atom()
        }

  @typedoc "A JSON API route mounted under `/api`."
  @type api_route :: %{
          required(:verb) => :get | :post | :patch | :put | :delete,
          required(:path) => String.t(),
          required(:controller) => module(),
          required(:action) => atom()
        }

  @doc "Unique module id, e.g. `:my_plate`. Used as config key and table-name prefix."
  @callback id() :: atom()

  @doc "Human-readable name shown in the UI and snapshot manifest."
  @callback title() :: String.t()

  @doc "Module version recorded in snapshot manifests."
  @callback version() :: String.t()

  @doc "Dashboard tile, or `nil` for no tile. Receives the module's config map."
  @callback dashboard_tile(config :: map()) :: Tile.t() | nil

  @doc "LiveView routes (absolute paths, e.g. `/my-plate`)."
  @callback ui_routes() :: [ui_route()]

  @doc "API routes (paths relative to `/api`, e.g. `/tasks`)."
  @callback api_routes() :: [api_route()]

  @doc "Directory containing this module's Ecto migrations."
  @callback migrations_path() :: String.t()

  @doc "List of `SapoKit.Scheduler.Hook` implementations."
  @callback scheduler_hooks() :: [module()]

  @doc "Child specs added to core's supervision tree. Receives the module's config map."
  @callback children(config :: map()) :: [Supervisor.child_spec() | {module(), term()} | module()]

  @doc """
  Storage is OPT-IN: the default `[]` means this module has no storage
  directory at all. Return a non-empty list to get a dedicated directory
  (`SapoKit.Storage.dir(id)`) — the entries are subdirectories to
  pre-create inside it, relative to it; return `["."]` for just the
  directory itself. Opted-in directories appear in the storage file API
  and in snapshots.
  """
  @callback storage_paths() :: [String.t()]

  @doc "Names of secret environment variables this module requires."
  @callback required_secrets() :: [String.t()]

  @doc "Markdown fragment for the AI assistant context, or `nil`."
  @callback ai_context() :: String.t() | nil

  @doc """
  Markdown fragment injected into the assistant's SYSTEM PROMPT at session
  start (composed across enabled modules in dependency order), or `nil`.
  Distinct from `ai_context/0`, which is pull-based via
  `/api/claude-context`. Keep it short: rules and pointers, not data.
  """
  @callback assistant_system_prompt() :: String.t() | nil

  @doc """
  A NimbleOptions-style schema validating this module's Nix-provided config.
  Validated at boot; return `[]` to accept anything.
  """
  @callback config_schema() :: keyword()

  defmacro __using__(_opts) do
    quote do
      @behaviour SapoKit.Module
      @sapo_otp_app Mix.Project.config()[:app]

      @impl true
      def version do
        case Application.spec(@sapo_otp_app, :vsn) do
          nil -> Mix.Project.config()[:version] || "0.0.0"
          vsn -> to_string(vsn)
        end
      end

      @impl true
      def dashboard_tile(_config), do: nil

      @impl true
      def ui_routes, do: []

      @impl true
      def api_routes, do: []

      @impl true
      def migrations_path do
        Application.app_dir(@sapo_otp_app, "priv/migrations")
      end

      @impl true
      def scheduler_hooks, do: []

      @impl true
      def children(_config), do: []

      @impl true
      def storage_paths, do: []

      @impl true
      def required_secrets, do: []

      @impl true
      def ai_context, do: nil

      @impl true
      def assistant_system_prompt, do: nil

      @impl true
      def config_schema, do: []

      defoverridable version: 0,
                     dashboard_tile: 1,
                     ui_routes: 0,
                     api_routes: 0,
                     migrations_path: 0,
                     scheduler_hooks: 0,
                     children: 1,
                     storage_paths: 0,
                     required_secrets: 0,
                     ai_context: 0,
                     assistant_system_prompt: 0,
                     config_schema: 0
    end
  end
end
