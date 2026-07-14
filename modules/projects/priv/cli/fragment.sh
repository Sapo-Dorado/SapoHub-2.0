# SapoHub CLI escape hatch: projects module.
#
# priv/cli/commands.exs declares list/show/create/delete generically.
# `scripts` (list runnable scripts on a project, run one with KEY=VALUE
# param overrides) and `params` (upsert/delete a project's stored script
# param) need request shapes the declarative spec doesn't cover — the
# generated sapo_cmd_projects dispatcher's fallback arm calls
# sapo_cmd_projects_ext for any action it doesn't recognize; this is that.
#
# NOTE: sudo-flagged scripts are intentionally not runnable from here (or
# anywhere else in this module) — see Projects.Module's moduledoc.

sapo_cmd_projects_ext() {
  local action="$1"; shift || true
  case "$action" in
    scripts)
      local sub="${1:-}"; shift || true
      case "$sub" in
        list)
          local id="${1:-}"
          [ -n "$id" ] || die "usage: sapo projects scripts list <project-id>"
          api_get "/projects/$id/scripts"
          ;;
        run)
          local id="${1:-}"; shift || true
          local file="${1:-}"; shift || true
          [ -n "$id" ] && [ -n "$file" ] || die "usage: sapo projects scripts run <project-id> <script-file> [KEY=VALUE...]"
          local params_json="{}"
          for kv in "$@"; do
            local key="${kv%%=*}"
            local value="${kv#*=}"
            params_json=$(jq -n --argjson base "$params_json" --arg k "$key" --arg v "$value" '$base + {($k): $v}')
          done
          local body
          body=$(jq -n --arg f "$file" --argjson p "$params_json" '{script_file: $f, params: $p}')
          api_post "/projects/$id/scripts/run" "$body"
          ;;
        *) die "usage: sapo projects scripts list <project-id> | run <project-id> <script-file> [KEY=VALUE...]" ;;
      esac
      ;;
    params)
      local sub="${1:-}"; shift || true
      case "$sub" in
        list)
          local id="${1:-}"
          [ -n "$id" ] || die "usage: sapo projects params list <project-id>"
          api_get "/projects/$id/params"
          ;;
        set)
          local id="${1:-}"; shift || true
          local key="${1:-}"; shift || true
          local value="${1:-}"; shift || true
          [ -n "$id" ] && [ -n "$key" ] || die "usage: sapo projects params set <project-id> <key> <value>"
          curl -sS -X PUT "$SAPO_API_BASE/projects/$id/params/$key" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg v "$value" '{value: $v}')" | json
          ;;
        delete)
          local id="${1:-}"; shift || true
          local key="${1:-}"
          [ -n "$id" ] && [ -n "$key" ] || die "usage: sapo projects params delete <project-id> <key>"
          api_delete "/projects/$id/params/$key"
          ;;
        *) die "usage: sapo projects params list <project-id> | set <project-id> <key> <value> | delete <project-id> <key>" ;;
      esac
      ;;
    *) die "usage: sapo projects list | show <id> | create <name> <github_url> | delete <id> | scripts ... | params ..." ;;
  esac
}
