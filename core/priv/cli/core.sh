#!/usr/bin/env bash
# sapo — the SapoHub CLI.
#
# This file is the CORE of the CLI: helpers, the dispatcher and core
# subcommands. The shipped `sapo` binary is this file concatenated with each
# enabled module's priv/cli/fragment.sh (dev: `mix sapo.gen.cli`;
# release: nix/cli.nix) followed by a final `sapo_main "$@"` line.
#
# Module fragments define:      sapo_cmd_<resource>() { ... }
# and append their help lines:  SAPO_CLI_HELP+="..."
# using the helpers below:      api_get/api_post/api_patch/api_delete, die

set -euo pipefail

SAPO_API_BASE="${SAPO_API_BASE:-http://localhost:4000/api}"

SAPO_CLI_HELP=""

die() { echo "sapo: $*" >&2; exit 1; }

# Pretty-print JSON when jq is available; pass through otherwise.
json() { jq . 2>/dev/null || cat; }

api_get()    { curl -sS "$SAPO_API_BASE$1" | json; }
api_delete() { curl -sS -X DELETE "$SAPO_API_BASE$1"; }
api_post() {
  local body="${2:-}"
  [ -n "$body" ] || body='{}'
  curl -sS -X POST -H 'Content-Type: application/json' \
    -d "$body" "$SAPO_API_BASE$1" | json
}
api_patch() {
  local body="${2:-}"
  [ -n "$body" ] || body='{}'
  curl -sS -X PATCH -H 'Content-Type: application/json' \
    -d "$body" "$SAPO_API_BASE$1" | json
}

sapo_help() {
  cat <<EOF
Usage: sapo <resource> <action> [args...]

Core:
  context     Print the AI context document
  notify      <message> [--destination <id>] [--image <path>]
  destinations  list | create --name <n> --channel <c> --config <json> |
                delete <id> | set-default <id>
  storage     list | get <path> [-o <file>] | delete <path>
  snapshot    list | save | download <name> [-o <file>]

Utilities:${SAPO_CLI_HELP:-
  (none)}

Environment:
  SAPO_API_BASE   API base URL (default: http://localhost:4000/api)
  SAPO_SESSION_ID Attached to notify calls automatically inside
                  assistant sessions
EOF
}

sapo_main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    -h|--help|help) sapo_help; return 0 ;;
  esac

  local fn="sapo_cmd_${cmd//-/_}"
  if declare -f "$fn" >/dev/null; then
    "$fn" "$@"
  else
    echo "sapo: unknown command '$cmd'" >&2
    sapo_help >&2
    return 1
  fi
}

# ── Core commands ─────────────────────────────────────────────────────────────

sapo_cmd_context() { curl -sS "$SAPO_API_BASE/claude-context"; }

sapo_cmd_notify() {
  [ $# -ge 1 ] || die "usage: sapo notify <message> [--destination <id>] [--image <path>]"

  local msg="$1" dest="" image=""
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --destination) dest="$2"; shift 2 ;;
      --image) image="$2"; shift 2 ;;
      *) die "notify: unknown option '$1'" ;;
    esac
  done

  local body
  body=$(jq -n \
    --arg m "$msg" --arg d "$dest" --arg i "$image" --arg s "${SAPO_SESSION_ID:-}" \
    '{message: $m}
     + (if $d != "" then {destination_id: $d} else {} end)
     + (if $i != "" then {image: $i} else {} end)
     + (if $s != "" then {session_id: $s} else {} end)')

  api_post /notify "$body"
}

sapo_cmd_snapshot() {
  local action="${1:-list}"
  shift || true
  case "$action" in
    list) api_get /snapshot ;;
    save) api_post /snapshot '{}' ;;
    download)
      [ -n "${1:-}" ] || die "usage: sapo snapshot download <name> [-o <file>]"
      local name="$1"
      shift
      curl -sS -o "${2:-$name}" "$SAPO_API_BASE/snapshot/$name"
      ;;
    *) die "usage: sapo snapshot list | save | download <name> [-o <file>]" ;;
  esac
}

sapo_cmd_storage() {
  local action="${1:-list}"
  shift || true
  case "$action" in
    list) api_get /storage/files ;;
    get)
      local path="${1:-}"
      [ -n "$path" ] || die "usage: sapo storage get <path> [-o <file>]"
      shift
      if [ "${1:-}" = "-o" ]; then
        curl -sS -o "$2" "$SAPO_API_BASE/storage/files/$path"
      else
        curl -sS "$SAPO_API_BASE/storage/files/$path"
      fi
      ;;
    delete) [ -n "${1:-}" ] || die "usage: sapo storage delete <path>"
      api_delete "/storage/files/$1" ;;
    *) die "usage: sapo storage list | get <path> [-o <file>] | delete <path>" ;;
  esac
}

# `destinations` (and other core resources that fit the <resource> <action>
# shape) are generated from priv/cli/commands.exs and appended below by
# `mix sapo.gen.cli` — see SapoCliGen. `notify` stays hand-written above
# since it's a flat `sapo notify <message> [flags]` command with no action
# word, which doesn't fit that generator's resource/action model.

# ── Module fragments are appended below by the CLI generator ─────────────────
