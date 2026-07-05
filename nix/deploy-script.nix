# sapohub-deploy — the ONE root-executed command (restricted sudoers).
#
# The config-repo path and flake attr are BAKED IN from the nix options, so
# no user-controlled paths ever reach root. The rebuild runs detached in a
# transient systemd unit (survives sapohub.service restarting itself), and
# the deploy streams the journal.
{ pkgs, lib }:

{ flakePath   # e.g. "/home/sapo/hub-config" (a git checkout)
, flakeAttr   # e.g. "nixos"
, stateDir    # e.g. "/var/lib/sapohub"
}:

pkgs.writeShellScriptBin "sapohub-deploy" ''
  set -euo pipefail
  export PATH="${lib.makeBinPath [
    pkgs.git pkgs.coreutils pkgs.systemd pkgs.nixos-rebuild pkgs.gzip
  ]}:$PATH"

  FLAKE_PATH="${flakePath}"
  FLAKE_ATTR="${flakeAttr}"
  STATE_DIR="${stateDir}"

  SNAPSHOT=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --snapshot)
        SNAPSHOT="$2"; shift 2 ;;
      *)
        echo "usage: sapohub-deploy [--snapshot <file>]" >&2; exit 1 ;;
    esac
  done

  # Stage a snapshot for boot-time restore (root-owned copy; the app's
  # Release.maybe_restore consumes it in ExecStartPre).
  if [ -n "$SNAPSHOT" ]; then
    [ -f "$SNAPSHOT" ] || { echo "snapshot not found: $SNAPSHOT" >&2; exit 1; }
    mkdir -p "$STATE_DIR/db/restore"
    cp "$SNAPSHOT" "$STATE_DIR/db/restore/pending.tar.gz"
    chmod 600 "$STATE_DIR/db/restore/pending.tar.gz"
    echo "snapshot staged for restore on next boot"
  fi

  git config --global --add safe.directory "$FLAKE_PATH" || true

  # Sync UI preference overlay into the config repo (prefs land as a real
  # nix module file; lib.mkDefault so hand-written config wins). The overlay
  # renderer arrives with the Prefs core service — sync is a no-op until
  # the overlay file exists.
  OVERLAY="$STATE_DIR/db/prefs-overlay.json"
  if [ -f "$OVERLAY" ]; then
    echo "NOTE: prefs overlay present but the renderer is not implemented yet; skipping sync"
  fi

  echo "pulling $FLAKE_PATH ..."
  git -C "$FLAKE_PATH" pull --ff-only

  echo "starting rebuild (detached; streaming journal — Ctrl-C safe) ..."
  systemd-run --unit=sapohub-deploy --collect --no-block \
    nixos-rebuild switch --flake "$FLAKE_PATH#$FLAKE_ATTR"

  exec journalctl -u sapohub-deploy -f --no-pager
''
