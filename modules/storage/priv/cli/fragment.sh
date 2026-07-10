# SapoHub CLI fragment: storage module
#
# Extends (overrides) core's base `sapo storage` command with `upload`,
# since uploading requires this module's own /storage/upload API route to
# actually be mounted. Fragments load after core.sh, so this definition
# simply replaces the base list/get/delete-only version when the module is
# enabled; when disabled, core's base version (no upload) is used instead.

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
    upload)
      local file="${1:-}"
      [ -n "$file" ] || die "usage: sapo storage upload <file>"
      [ -f "$file" ] || die "sapo storage upload: no such file: $file"
      curl -sS -X POST -F "file=@$file" "$SAPO_API_BASE/storage/upload" | json
      ;;
    *) die "usage: sapo storage list | get <path> [-o <file>] | delete <path> | upload <file>" ;;
  esac
}
