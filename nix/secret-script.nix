# sapohub-set-secret — the other root-executed command (restricted
# sudoers), alongside sapohub-deploy. Lets the Settings page write to the
# root-only secrets file without ever giving the app process (runs as the
# unprivileged `sapohub` user, same as everything else) read or write
# access to that file directly.
#
# Two rules that matter for how this is called:
#   * The secret VALUE is only ever read from stdin, never argv — argv is
#     visible to any other local user via `ps`, stdin isn't.
#   * Only a fixed allowlist of variable names is accepted (see ALLOWED
#     below), so a compromised/buggy caller can't use this to inject an
#     arbitrary key into a file that's also loaded as a systemd
#     EnvironmentFile at boot. Keep this list in sync with the Settings
#     page's own allowlist (settings_live.ex, @settable_secrets) — each
#     side checking independently is the point, not redundant.
#
# This never prints the secret value itself, on any code path — --status
# answers "set"/"missing" only, --set answers "ok" only.
{ pkgs, lib }:

{ secretsFile }:

pkgs.writeShellScriptBin "sapohub-set-secret" ''
  set -euo pipefail
  export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep ]}:$PATH"

  SECRETS_FILE="${secretsFile}"

  usage() {
    echo "usage: sapohub-set-secret --status <VAR>" >&2
    echo "       sapohub-set-secret --set <VAR>     (value read from stdin)" >&2
    exit 1
  }

  [ $# -eq 2 ] || usage
  MODE="$1"
  VAR="$2"

  case "$VAR" in
    GITHUB_TOKEN) : ;;
    *) echo "unknown secret: $VAR" >&2; exit 1 ;;
  esac

  mkdir -p "$(dirname "$SECRETS_FILE")"
  touch "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"

  case "$MODE" in
    --status)
      VALUE="$(grep -m1 "^$VAR=" "$SECRETS_FILE" | cut -d= -f2- || true)"
      if [ -n "$VALUE" ]; then echo set; else echo missing; fi
      ;;

    --set)
      # `read` (not `cat`) so this only ever needs ONE line terminated by
      # \n on stdin, not a full EOF/close — the caller (settings_live.ex)
      # writes to an Erlang Port it never closes early, since closing a
      # port also cuts off the ability to read this script's own
      # stdout/exit status back.
      IFS= read -r VALUE
      [ -n "$VALUE" ] || { echo "empty value" >&2; exit 1; }

      TMP="$(mktemp "$(dirname "$SECRETS_FILE")/.secrets.XXXXXX")"
      trap 'rm -f "$TMP"' EXIT
      grep -v "^$VAR=" "$SECRETS_FILE" > "$TMP" || true
      printf '%s=%s\n' "$VAR" "$VALUE" >> "$TMP"
      chmod 600 "$TMP"
      mv "$TMP" "$SECRETS_FILE"
      echo ok
      ;;

    *) usage ;;
  esac
''
