# SapoHub CLI fragment: hello module
# Defines sapo_cmd_<resource> functions and appends to SAPO_CLI_HELP.

SAPO_CLI_HELP+="
  hello       list | create <name> | delete <id>
"

sapo_cmd_hello() {
  local action="$1"; shift || true
  case "$action" in
    list)
      api_get "/hello"
      ;;
    create)
      [ -n "$1" ] || die "usage: sapo hello create <name>"
      api_post "/hello" "$(jq -n --arg name "$1" '{name: $name}')"
      ;;
    delete)
      [ -n "$1" ] || die "usage: sapo hello delete <id>"
      api_delete "/hello/$1"
      ;;
    *)
      die "usage: sapo hello list | create <name> | delete <id>"
      ;;
  esac
}
