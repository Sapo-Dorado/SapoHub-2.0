# SapoHub CLI fragment: my_plate module

SAPO_CLI_HELP+="
  tasks       list [--priority high|medium|low] | show <id> | create <title> [--priority <p>] [--due YYYY-MM-DD] |
              complete <id> | uncomplete <id> | delete <id>
  recurring   list | create <title> --recurrence daily|weekly|monthly [--priority <p>]
              [--day-of-week 1-7] [--day-of-month 1-31] | delete <id>
"

sapo_cmd_tasks() {
  local action="${1:-list}"
  shift || true
  case "$action" in
    list)
      if [ "${1:-}" = "--priority" ]; then
        api_get "/tasks?priority=$2"
      else
        api_get "/tasks"
      fi
      ;;
    show)
      [ -n "${1:-}" ] || die "usage: sapo tasks show <id>"
      api_get "/tasks/$1"
      ;;
    create)
      [ -n "${1:-}" ] || die "usage: sapo tasks create <title> [--priority <p>] [--due YYYY-MM-DD]"
      local title="$1" priority="medium" due=""
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          --priority) priority="$2"; shift 2 ;;
          --due) due="$2"; shift 2 ;;
          *) die "tasks create: unknown option '$1'" ;;
        esac
      done
      api_post "/tasks" "$(jq -n --arg t "$title" --arg p "$priority" --arg d "$due" \
        '{title: $t, priority: $p} + (if $d != "" then {due_date: $d} else {} end)')"
      ;;
    complete)
      [ -n "${1:-}" ] || die "usage: sapo tasks complete <id>"
      api_post "/tasks/$1/complete" '{}'
      ;;
    uncomplete)
      [ -n "${1:-}" ] || die "usage: sapo tasks uncomplete <id>"
      api_post "/tasks/$1/uncomplete" '{}'
      ;;
    delete)
      [ -n "${1:-}" ] || die "usage: sapo tasks delete <id>"
      api_delete "/tasks/$1"
      ;;
    *)
      die "usage: sapo tasks list|show <id>|create <title>|complete <id>|uncomplete <id>|delete <id>"
      ;;
  esac
}

sapo_cmd_recurring() {
  local action="${1:-list}"
  shift || true
  case "$action" in
    list) api_get "/recurring-tasks" ;;
    create)
      [ -n "${1:-}" ] || die "usage: sapo recurring create <title> --recurrence <r> [...]"
      local title="$1" priority="medium" recurrence="" dow="" dom=""
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          --priority) priority="$2"; shift 2 ;;
          --recurrence) recurrence="$2"; shift 2 ;;
          --day-of-week) dow="$2"; shift 2 ;;
          --day-of-month) dom="$2"; shift 2 ;;
          *) die "recurring create: unknown option '$1'" ;;
        esac
      done
      [ -n "$recurrence" ] || die "recurring create: --recurrence is required"
      api_post "/recurring-tasks" "$(jq -n --arg t "$title" --arg p "$priority" \
        --arg r "$recurrence" --arg dw "$dow" --arg dm "$dom" \
        '{title: $t, priority: $p, recurrence: $r}
         + (if $dw != "" then {day_of_week: ($dw | tonumber)} else {} end)
         + (if $dm != "" then {day_of_month: ($dm | tonumber)} else {} end)')"
      ;;
    delete)
      [ -n "${1:-}" ] || die "usage: sapo recurring delete <id>"
      api_delete "/recurring-tasks/$1"
      ;;
    *)
      die "usage: sapo recurring list|create <title> --recurrence <r>|delete <id>"
      ;;
  esac
}
