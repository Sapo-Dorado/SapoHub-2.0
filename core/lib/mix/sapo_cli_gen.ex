defmodule SapoCliGen do
  @moduledoc """
  Generates `sapo_cmd_<resource>` bash functions from a declarative spec, so
  a module can define its CLI as data (`priv/cli/commands.exs`) instead of
  hand-written bash. Used by `mix sapo.gen.cli` (dev) and the release build
  (`nix/compose.nix`) — both just call `generate/1` and concatenate the
  result the same way `priv/cli/fragment.sh` content was concatenated
  before.

  ## Spec format

  `commands.exs` evaluates to a list of resource maps:

      [
        %{
          name: "tasks",
          help: "list [--priority high|medium|low] | show <id> | ...",
          actions: [
            %{action: "list", verb: :list, path: "/tasks",
              params: [%{key: :priority, flag: "--priority"}]},
            %{action: "show", verb: :show, path: "/tasks/:id"},
            %{action: "create", verb: :create, path: "/tasks", args: [:title],
              params: [
                %{key: :priority, flag: "--priority", default: "medium"},
                %{key: :due_date, flag: "--due"}
              ]},
            %{action: "complete", verb: :create, path: "/tasks/:id/complete"},
            %{action: "delete", verb: :delete, path: "/tasks/:id"}
          ]
        }
      ]

  `name` — the subcommand word (`sapo tasks ...`).
  `help` — one usage line, appended to `sapo help`'s Utilities section.
  `actions` — each becomes one arm of the resource's `case "$action" in`:

    * `:list`   — `GET <path>`, optional `params` become `?key=value` query args
    * `:show`   — `GET <path>` (`:id` in path filled from the first
      positional); `output: true` also allows a trailing `-o <file>` to save
      the raw response instead of piping through `jq`
    * `:create` — `POST <path>`; `args` are required positionals (in order,
      become body fields), `params` are optional `--flag value` (become body
      fields, or omitted if not passed and no `default`); if `path` contains
      `:id`, the first positional fills it instead of `args`. A `:create`
      action with no `args`/`params` at all (e.g. `complete`) just POSTs
      `{}` — this is also how the "empty-body action on an id" shape
      (complete/uncomplete/set-default/...) is expressed.
    * `:update` — same body-building as `:create`, but `PATCH`
    * `:delete` — `DELETE <path>` (`:id` filled from the first positional)
    * `:upload` — multipart `POST <path>` with a required file positional
      (`field:` sets the form field name, default `"file"`)

  `params` entries: `%{key:, flag:, default:, required:, type:}` — `type:
  :integer` coerces via jq's `tonumber`; `required: true` dies with a usage
  message if the flag is missing; `default:` is used when the flag is
  omitted (and makes the field always present in the body).

  ## Escape hatch

  If a resource needs something outside this vocabulary (SapoStorage's
  `upload`, which needs a raw multipart request with a fixed field name
  read from a local file — actually expressible above, but some genuinely
  custom shape might not be), the generated dispatcher's fallback arm calls
  `sapo_cmd_<name>_ext "$action" "$@"` if that function is defined. A module
  can still ship `priv/cli/fragment.sh` defining just that one function,
  handling only the actions the declarative spec doesn't cover — it's
  concatenated after the generated code, so it loads in time to be found by
  `declare -f`.
  """

  @spec generate([map()]) :: String.t()
  def generate(resources) when is_list(resources) do
    Enum.map_join(resources, "\n", &generate_resource/1)
  end

  defp generate_resource(%{name: name, actions: actions} = resource) do
    help = Map.get(resource, :help, "")
    fn_name = "sapo_cmd_#{bash_ident(name)}"

    arms = Enum.map_join(actions, "\n", &generate_action(name, &1))

    help_block =
      if help == "" do
        ""
      else
        """
        SAPO_CLI_HELP+="
          #{pad(name)}#{help}
        "

        """
      end

    """
    #{help_block}#{fn_name}() {
      local action="${1:-list}"
      shift || true
      case "$action" in
    #{indent(arms, 4)}
        *)
          if declare -f #{fn_name}_ext >/dev/null; then
            #{fn_name}_ext "$action" "$@"
          else
            die "usage: sapo #{name} #{usage_summary(resource)}"
          fi
          ;;
      esac
    }
    """
  end

  defp pad(name) when byte_size(name) >= 12, do: name <> " "
  defp pad(name), do: String.pad_trailing(name, 12)

  defp usage_summary(%{actions: actions} = resource) do
    case Map.get(resource, :help) do
      nil -> Enum.map_join(actions, " | ", & &1.action)
      help -> help
    end
  end

  # ── Per-verb codegen ─────────────────────────────────────────────────────

  defp generate_action(_name, %{action: action, verb: :list} = a) do
    path = Map.fetch!(a, :path)
    params = Map.get(a, :params, [])

    query =
      if params == [] do
        ""
      else
        cases =
          Enum.map_join(params, "\n", fn p ->
            ~s(      #{p.flag}) <> ") qs=\"${qs}&#{p.key}=$2\"; shift 2 ;;"
          end)

        """
        local qs=""
        while [ $# -gt 0 ]; do
          case "$1" in
        #{cases}
            *) die "usage: sapo <resource> #{action} #{flags_usage(params)}" ;;
          esac
        done
        """
      end

    get_line =
      if params == [],
        do: ~s(api_get "#{path}"),
        else: ~s(api_get "#{path}${qs:+?${qs#&}}")

    """
    #{action})
    #{indent(query, 2)}  #{get_line}
      ;;
    """
  end

  defp generate_action(_name, %{action: action, verb: :show} = a) do
    path = Map.fetch!(a, :path)
    output = Map.get(a, :output, false)
    url = interpolate_id(path)

    fetch =
      if output do
        """
        shift
        if [ "${1:-}" = "-o" ]; then
          curl -sS -o "$2" "$SAPO_API_BASE#{url}"
        else
          curl -sS "$SAPO_API_BASE#{url}"
        fi
        """
      else
        ~s(api_get "#{url}"\n)
      end

    usage = if output, do: "#{action} <id> [-o <file>]", else: "#{action} <id>"

    """
    #{action})
      local id="${1:-}"
      [ -n "$id" ] || die "usage: sapo <resource> #{usage}"
    #{indent(fetch, 2)}  ;;
    """
  end

  defp generate_action(_name, %{action: action, verb: :delete} = a) do
    path = Map.fetch!(a, :path)
    url = interpolate_id(path)

    """
    #{action})
      local id="${1:-}"
      [ -n "$id" ] || die "usage: sapo <resource> #{action} <id>"
      api_delete "#{url}"
      ;;
    """
  end

  defp generate_action(_name, %{action: action, verb: verb} = a) when verb in [:create, :update] do
    path = Map.fetch!(a, :path)
    args = Map.get(a, :args, [])
    params = Map.get(a, :params, [])
    has_id = String.contains?(path, ":id")
    url = interpolate_id(path)
    method_fn = if verb == :create, do: "api_post", else: "api_patch"

    id_capture =
      if has_id do
        """
        local id="${1:-}"
        [ -n "$id" ] || die "usage: sapo <resource> #{usage_line(action, args, params, has_id)}"
        shift
        """
      else
        ""
      end

    positional_captures =
      args
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {arg, _i} ->
        ~s(local #{arg}="${1:-}") <>
          "\n" <>
          ~s([ -n "$#{arg}" ] || die "usage: sapo <resource> #{usage_line(action, args, params, has_id)}") <>
          "\nshift"
      end)

    param_defaults =
      Enum.map_join(params, "\n", fn p ->
        default = Map.get(p, :default)
        ~s(local #{p.key}="#{default}")
      end)

    param_loop =
      if params == [] do
        ""
      else
        cases =
          Enum.map_join(params, "\n", fn p ->
            ~s(      #{p.flag}) <> ") #{p.key}=\"$2\"; shift 2 ;;"
          end)

        """
        while [ $# -gt 0 ]; do
          case "$1" in
        #{cases}
            *) die "#{action}: unknown option '$1'" ;;
          esac
        done
        """
      end

    required_checks =
      params
      |> Enum.filter(&Map.get(&1, :required, false))
      |> Enum.map_join("\n", fn p ->
        ~s([ -n "$#{p.key}" ] || die "#{action}: #{p.flag} is required")
      end)

    body = build_body_expr(args, params)

    """
    #{action})
    #{indent(id_capture, 2)}#{indent(positional_captures, 2)}
    #{indent(param_defaults, 2)}
    #{indent(param_loop, 2)}
    #{indent(required_checks, 2)}
      #{method_fn} "#{url}" #{body}
      ;;
    """
  end

  defp generate_action(_name, %{action: action, verb: :upload} = a) do
    path = Map.fetch!(a, :path)
    field = Map.get(a, :field, "file")

    """
    #{action})
      local file="${1:-}"
      [ -n "$file" ] || die "usage: sapo <resource> #{action} <file>"
      [ -f "$file" ] || die "sapo <resource> #{action}: no such file: $file"
      curl -sS -X POST -F "#{field}=@$file" "$SAPO_API_BASE#{path}" | json
      ;;
    """
  end

  # ── Body building (create/update) ────────────────────────────────────────

  defp build_body_expr([], []), do: "'{}'"

  defp build_body_expr(args, params) do
    arg_flags = Enum.map_join(args, " ", fn a -> ~s(--arg #{a} "$#{a}") end)
    param_flags = Enum.map_join(params, " ", fn p -> ~s(--arg #{p.key} "$#{p.key}") end)

    required_fields =
      Enum.map_join(args, ", ", fn a -> "#{a}: $#{a}" end)

    always_present =
      params
      |> Enum.filter(&Map.has_key?(&1, :default))
      |> Enum.map_join("", fn p -> ", #{p.key}: #{jq_value(p)}" end)

    optional_fields =
      params
      |> Enum.reject(&Map.has_key?(&1, :default))
      |> Enum.map_join("", fn p ->
        " + (if $#{p.key} != \"\" then {#{p.key}: #{jq_value(p)}} else {} end)"
      end)

    base = if required_fields == "", do: "{}", else: "{#{required_fields}#{always_present}}"

    flags = String.trim("#{arg_flags} #{param_flags}")
    flags = if flags == "", do: "", else: flags <> " "

    "\"$(jq -n #{flags}'#{base}#{optional_fields}')\""
  end

  defp jq_value(%{type: :integer, key: key}), do: "($#{key}|tonumber)"
  defp jq_value(%{key: key}), do: "$#{key}"

  # ── Small helpers ─────────────────────────────────────────────────────────

  defp interpolate_id(path), do: String.replace(path, ":id", "$id")

  defp flags_usage(params), do: Enum.map_join(params, " ", &"[#{&1.flag} <#{&1.key}>]")

  defp usage_line(action, args, params, has_id) do
    id_part = if has_id, do: "<id> ", else: ""
    args_part = Enum.map_join(args, " ", &"<#{&1}>")
    flags_part = flags_usage(params)
    [action, id_part, args_part, flags_part] |> Enum.join(" ") |> String.trim()
  end

  defp bash_ident(name), do: String.replace(name, "-", "_")

  defp indent(text, spaces) do
    pad = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> pad <> line
    end)
  end
end
