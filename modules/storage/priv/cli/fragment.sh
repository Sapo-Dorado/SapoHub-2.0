# SapoHub CLI escape hatch: storage module.
#
# priv/cli/commands.exs declares list/get/delete generically; `upload`
# needs a raw multipart request tied to this module's own /storage/upload
# route, which isn't one of SapoCliGen's standard verbs. The generated
# sapo_cmd_storage dispatcher's fallback arm calls sapo_cmd_storage_ext for
# any action it doesn't recognize — this is that.

sapo_cmd_storage_ext() {
  local action="$1"; shift || true
  case "$action" in
    upload)
      local file="${1:-}"
      [ -n "$file" ] || die "usage: sapo storage upload <file>"
      [ -f "$file" ] || die "sapo storage upload: no such file: $file"
      curl -sS -X POST -F "file=@$file" "$SAPO_API_BASE/storage/upload" | json
      ;;
    *) die "usage: sapo storage list | get <path> [-o <file>] | delete <path> | upload <file>" ;;
  esac
}
