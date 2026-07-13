defmodule Mix.Tasks.Sapo.Gen.Module do
  @shortdoc "Generates a new SapoHub util module skeleton"

  @moduledoc """
  Generates a new util module implementing the `SapoKit.Module` contract.

      mix sapo.gen.module my_thing
      mix sapo.gen.module my_thing --title "My Thing" --path ../modules/my_thing

  Options:

    * `--title` - human-readable name (default: camelized app name)
    * `--path` - target directory (default: `../modules/<name>` relative to core)
    * `--kit-path` - path from the target dir to the contract package
      (default: `../../contract`, correct for in-repo modules)

  After generating, enable the module by adding it to
  `core/config/modules.lock.exs` and `core/lib/sapo_core/generated/registry.ex`.
  """

  use Mix.Task

  @impl true
  def run(args) do
    {opts, argv} =
      OptionParser.parse!(args, strict: [title: :string, path: :string, kit_path: :string])

    case argv do
      [name] ->
        unless name =~ ~r/^[a-z][a-z0-9_]*$/ do
          Mix.raise("module name must be snake_case (got #{inspect(name)})")
        end

        target = opts[:path] || Path.expand("../modules/#{name}", File.cwd!())

        if File.exists?(target) do
          Mix.raise("target directory already exists: #{target}")
        end

        for {rel_path, content} <- files(name, opts) do
          path = Path.join(target, rel_path)
          Mix.Generator.create_file(path, content)
        end

        Mix.shell().info("""

        Module generated at #{target}.

        To enable it:

          1. Add {:#{name}, "#{Path.relative_to(target, File.cwd!())}"} to core/config/modules.lock.exs
             (paths are relative to the lock file's directory — prefix with ../)
          2. Add #{camelize(name)}.Module to core/lib/sapo_core/generated/registry.ex
             (both modules() and module_config())
          3. mix deps.get && mix sapo.migrate
        """)

      _ ->
        Mix.raise("usage: mix sapo.gen.module <snake_case_name> [--title T] [--path P]")
    end
  end

  @doc "Returns the map of relative path => file content for a new module."
  def files(name, opts \\ []) do
    module = camelize(name)
    title = opts[:title] || module
    kit_path = opts[:kit_path] || "../../contract"
    route = "/" <> String.replace(name, "_", "-")

    %{
      "mix.exs" => mix_exs(name, module, kit_path),
      "README.md" => readme(name, title),
      "lib/#{name}/module.ex" => module_ex(name, module, title, route),
      "lib/#{name}.ex" => context_ex(module),
      "lib/#{name}_web/live/index.ex" => live_index(module, title),
      "priv/migrations/.gitkeep" => "",
      "priv/cli/commands.exs" => cli_commands(name),
      "assets/hooks.js" => hooks_js()
    }
  end

  defp camelize(name), do: Macro.camelize(name)

  defp mix_exs(name, module, kit_path) do
    """
    defmodule #{module}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{name},
          version: "0.1.0",
          elixir: "~> 1.15",
          start_permanent: Mix.env() == :prod,
          deps: deps()
        ]
      end

      def application do
        [
          extra_applications: [:logger]
        ]
      end

      # A util module depends only on the SapoHub module kit.
      defp deps do
        [
          {:sapo_module_kit, path: "#{kit_path}"}
        ]
      end
    end
    """
  end

  defp readme(name, title) do
    """
    # #{title}

    A SapoHub util module. Implements the `SapoKit.Module` contract in
    `lib/#{name}/module.ex` — see `modules/hello` for a fully worked example
    and `docs/module-authoring.md` for the contract reference.
    """
  end

  defp module_ex(name, module, title, route) do
    """
    defmodule #{module}.Module do
      @moduledoc \"\"\"
      SapoKit.Module implementation for #{title}.

      Only `id/0` and `title/0` are required; every other callback has a
      default. Common overrides:

        * `api_routes/0` - JSON API endpoints under /api
        * `migrations_path/0` - defaults to priv/migrations
        * `scheduler_hooks/0` - periodic work via the core scheduler
        * `children/1` - module-owned processes in the supervision tree
        * `storage_paths/0` - owned dirs under the storage root (snapshotted)
        * `required_secrets/0` - env vars validated at boot
        * `ai_context/0` - markdown fragment for the assistant context
        * `config_schema/0` - validates nix-provided module options
      \"\"\"
      use SapoKit.Module

      @impl true
      def id, do: :#{name}

      @impl true
      def title, do: "#{title}"

      @impl true
      def dashboard_tile(config) do
        %SapoKit.Tile{
          label: "#{title}",
          icon: "hero-squares-2x2",
          path: "#{route}",
          style: config[:tile_style] || :standard
        }
      end

      @impl true
      def ui_routes do
        [%{path: "#{route}", live_view: #{module}Web.Live.Index, action: :index}]
      end

      @impl true
      def config_schema do
        [tile_style: [type: {:in, [:standard, :wide, :accent]}, default: :standard]]
      end
    end
    """
  end

  defp context_ex(module) do
    """
    defmodule #{module} do
      @moduledoc \"\"\"
      Context for #{module}: business logic and database access
      (through `SapoKit.Repo`).
      \"\"\"
    end
    """
  end

  defp live_index(module, title) do
    crumb = String.downcase(title)

    """
    defmodule #{module}Web.Live.Index do
      use SapoKit.Web, :live_view

      @impl true
      def mount(_params, _session, socket) do
        {:ok, socket}
      end

      @impl true
      def render(assigns) do
        ~H\"\"\"
        <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
          <SapoCoreWeb.Statusline.statusline crumb="#{crumb}" items={@statusline} />
          <SapoCoreWeb.Layouts.flash_group flash={@flash} />

          <main class="max-w-[640px] mx-auto px-4 py-8 space-y-6">
            <div class="flex items-center gap-2.5 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
              <span>#{title}</span>
              <span class="h-px flex-1 bg-[#242D31]"></span>
            </div>
          </main>
        </div>
        \"\"\"
      end
    end
    """
  end

  defp cli_commands(name) do
    """
    # SapoHub CLI commands: #{name} module (declarative — see SapoCliGen).
    #
    # Each entry becomes a `sapo <name> <action> ...` subcommand, generated
    # into plain bash by `mix sapo.gen.cli`. Delete this file (and the
    # priv/cli/ directory) if the module has no CLI commands.
    #
    # Supported verbs: :list, :show, :create, :update, :delete, :upload —
    # see core/lib/mix/sapo_cli_gen.ex's moduledoc for the full spec format.
    # If an action doesn't fit these verbs (a raw multipart request, a
    # custom response shape, ...), leave it out here and instead define
    # `sapo_cmd_#{name}_ext()` in priv/cli/fragment.sh — the generated
    # dispatcher's fallback arm calls it automatically.
    #
    # Example:
    #
    # [
    #   %{
    #     name: "#{name}",
    #     help: "list | show <id> | create <title> | delete <id>",
    #     actions: [
    #       %{action: "list", verb: :list, path: "/#{name}"},
    #       %{action: "show", verb: :show, path: "/#{name}/:id"},
    #       %{action: "create", verb: :create, path: "/#{name}", args: [:title]},
    #       %{action: "delete", verb: :delete, path: "/#{name}/:id"}
    #     ]
    #   }
    # ]

    []
    """
  end

  defp hooks_js do
    """
    // LiveView JS hooks contributed by this module (composed into core's
    // bundle by nix). Keep hooks framework-free.
    export default {};
    """
  end
end
