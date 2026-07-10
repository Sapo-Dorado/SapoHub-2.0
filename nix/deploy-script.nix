# sapohub-deploy — the ONE root-executed command (restricted sudoers).
#
# The config-repo path and flake attr are BAKED IN from the nix options, so
# no user-controlled paths ever reach root. The rebuild runs detached in a
# transient systemd unit (survives sapohub.service restarting itself), and
# the deploy streams the journal.
#
# Nix/git is the source of truth by default: a bare `sapohub-deploy` run
# (by hand over SSH, cron, whatever) pulls the config repo and rebuilds
# from EXACTLY what's there — it never lets a local runtime overlay of UI
# preferences override hand-written config. Only `--sync-prefs` opts in to
# writing that overlay back into the repo first; the Settings "Deploy"
# button is the one caller that passes it (see core/config/runtime.exs).
{ pkgs, lib }:

{ flakePath   # e.g. "/home/sapo/hub-config" (a git checkout)
, flakeAttr   # e.g. "nixos"
, stateDir    # e.g. "/var/lib/sapohub"
, secretsFile # e.g. "/etc/sapohub/secrets.env" — root-only; may hold GITHUB_TOKEN
}:

let
  # Runs the actual rebuild and records its outcome. Kept as its own
  # script (rather than an inline `bash -c '...'` string passed to
  # systemd-run) to sidestep nested-quoting hazards, and — more
  # importantly — so it can be started detached via systemd-run and
  # keep running (and reliably write the result file) even if
  # sapohub.service itself gets restarted mid-rebuild and kills the
  # outer sapohub-deploy script that launched it. Takes the flake
  # path/attr and status-file path via env vars (set with
  # --setenv by the caller) rather than argv, to match this file's
  # existing rule about root-executed commands not taking
  # caller-controlled paths as arguments.
  runRebuild = pkgs.writeShellScript "sapohub-deploy-rebuild" ''
    set -uo pipefail
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.nixos-rebuild ]}:$PATH"
    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if nixos-rebuild switch --flake "$FLAKE_PATH#$FLAKE_ATTR"; then
      STATUS=success
    else
      STATUS=failed
    fi
    printf '{"at":"%s","status":"%s"}\n' "$NOW" "$STATUS" > "$STATUS_FILE.tmp"
    mv -f "$STATUS_FILE.tmp" "$STATUS_FILE"
    [ "$STATUS" = success ]
  '';
in

pkgs.writeShellScriptBin "sapohub-deploy" ''
  set -euo pipefail
  export PATH="${lib.makeBinPath [
    pkgs.bash pkgs.git pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.systemd pkgs.nixos-rebuild pkgs.gzip pkgs.jq
  ]}:$PATH"

  FLAKE_PATH="${flakePath}"
  FLAKE_ATTR="${flakeAttr}"
  STATE_DIR="${stateDir}"
  SECRETS_FILE="${secretsFile}"

  # Persist everything this script prints to a log file from the very
  # first line, IN ADDITION to the PTY the browser terminal is attached
  # to. The PTY is the only place this output is normally visible — if
  # the CommandSession GenServer exits (of its own accord, or because a
  # rebuild restarts sapohub.service and kills it), that live view is
  # gone for good and there's no way to tell why a fast failure happened
  # after the fact. This makes every run forensically reviewable via
  # `cat $STATE_DIR/db/last-deploy-output.log` regardless of what the
  # browser saw or missed.
  mkdir -p "$STATE_DIR/db"
  LOG_FILE="$STATE_DIR/db/last-deploy-output.log"
  exec > >(tee "$LOG_FILE") 2>&1

  # GITHUB_TOKEN (if present in the root-only secrets file) authenticates
  # the config-repo push below. This script already runs as root, so
  # reading a root-owned 0600 file here doesn't widen access to anything.
  # Optional: no token just means the --sync-prefs commit below succeeds
  # locally but can't push (same as today, before this existed).
  GITHUB_TOKEN=""
  if [ -r "$SECRETS_FILE" ]; then
    GITHUB_TOKEN="$(grep -m1 '^GITHUB_TOKEN=' "$SECRETS_FILE" | cut -d= -f2- || true)"
  fi

  SNAPSHOT=""
  SYNC_PREFS=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --snapshot)
        SNAPSHOT="$2"; shift 2 ;;
      --sync-prefs)
        SYNC_PREFS="1"; shift ;;
      *)
        echo "usage: sapohub-deploy [--snapshot <file>] [--sync-prefs]" >&2; exit 1 ;;
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

  echo "pulling $FLAKE_PATH ..."
  # One retry on a bare transient failure (e.g. a momentary GitHub/network
  # blip) before giving up — a `git pull` failure here aborts the whole
  # script in well under a second (nothing else has run yet), which reads
  # to anyone watching as "the deploy just vanished" even though it's
  # really just a fetch that should be retried.
  if ! git -C "$FLAKE_PATH" pull --ff-only; then
    echo "pull failed, retrying once ..." >&2
    sleep 2
    git -C "$FLAKE_PATH" pull --ff-only
  fi

  # Sync the UI preference overlay into the config repo as a REAL nix
  # module file (lib.mkDefault, so hand-written config always wins). The
  # user's flake imports ./sapohub-prefs.nix. After a successful sync the
  # overlay is consumed — the nix config now carries the prefs.
  #
  # ONLY when --sync-prefs is passed. Without it (the default — any bare
  # manual run) this whole step is skipped: the overlay file is left
  # exactly as-is (nothing lost, still live at runtime, still there for a
  # future --sync-prefs run) and the rebuild below uses whatever's
  # already committed in the config repo, unmodified. That's what makes
  # git/nix authoritative for manual deploys.
  OVERLAY="$STATE_DIR/db/prefs-overlay.json"
  if [ "$SYNC_PREFS" = "1" ] && [ -f "$OVERLAY" ] && [ -s "$OVERLAY" ]; then
    echo "syncing UI preferences into $FLAKE_PATH/sapohub-prefs.nix ..."

    BASE="{}"
    [ -f /etc/sapohub/prefs.json ] && BASE=$(cat /etc/sapohub/prefs.json)
    MERGED=$(jq -S -n --argjson base "$BASE" --argjson overlay "$(cat "$OVERLAY")" \
      '$base + $overlay')

    cat > "$FLAKE_PATH/sapohub-prefs.nix" <<NIXEOF
  # GENERATED by sapohub-deploy — UI preferences synced from the hub.
  # lib.mkDefault: anything you set on services.sapohub.prefs directly wins.
  { lib, ... }:
  {
    services.sapohub.prefs = lib.mapAttrs (_: lib.mkDefault) (builtins.fromJSON '''
  $MERGED
  ''');
  }
  NIXEOF

    git -C "$FLAKE_PATH" add sapohub-prefs.nix
    if ! git -C "$FLAKE_PATH" diff --cached --quiet; then
      # This runs as root via sudo, whose git identity is never
      # otherwise configured on a fresh machine — `git commit` would
      # abort with "Please tell me who you are" before ever reaching
      # the rebuild. Pass an explicit identity so this automated
      # commit never depends on host git config existing.
      git -c user.name="sapohub-deploy" -c user.email="sapohub-deploy@localhost" \
        -C "$FLAKE_PATH" commit -m "sapohub: sync UI preferences"

      if [ -n "$GITHUB_TOKEN" ]; then
        # Push over an authenticated URL built just for this one push —
        # never written to $FLAKE_PATH/.git/config, never in an argv any
        # non-root process could read (this whole script only runs as
        # root already).
        REMOTE_URL="$(git -C "$FLAKE_PATH" remote get-url origin)"
        AUTH_URL="$(printf '%s' "$REMOTE_URL" | sed "s|https://|https://x-access-token:$GITHUB_TOKEN@|")"
        git -C "$FLAKE_PATH" push "$AUTH_URL"
      else
        # Deliberately NOT attempting a bare `git push` here — without a
        # token it's certain to fail ("could not read Username"), and
        # under `set -e` that would abort the whole script before ever
        # reaching the rebuild below. The commit stays local; it'll push
        # next time --sync-prefs runs with a token present.
        echo "GITHUB_TOKEN not set in $SECRETS_FILE — commit made locally but not pushed" >&2
      fi
    fi
    rm -f "$OVERLAY"
  elif [ -f "$OVERLAY" ] && [ -s "$OVERLAY" ]; then
    echo "skipping UI preference sync (no --sync-prefs) — git/nix config takes precedence"
  fi

  echo "starting rebuild (detached; streaming journal) ..."
  mkdir -p "$STATE_DIR/db"
  STATUS_FILE="$STATE_DIR/db/last-deploy.json"
  MARKER="$STATE_DIR/db/.last-deploy.marker"
  # Recorded BEFORE the rebuild starts so we can tell a fresh STATUS_FILE
  # write (below) apart from a stale one left by a previous run.
  touch "$MARKER"

  # The rebuild runs detached (--no-block, --collect) so it survives
  # sapohub.service restarting itself mid-rebuild (nixos-rebuild switch
  # will restart sapohub.service if the app's own derivation changed,
  # which would otherwise kill this very script, a child of that
  # service, partway through). Because of that, the result MUST be
  # recorded from *inside* the detached unit itself — anything this
  # outer script does after systemd-run returns can just as easily be
  # killed by that same restart, and often is.
  #
  # systemd-run does NOT inherit this script's PATH — transient units
  # start with systemd's own minimal default env, not the invoking
  # shell's. That silently broke nixos-rebuild-ng, which shells out to
  # the `test` coreutils binary internally and can't find it without
  # coreutils on PATH: it failed deep into the build with "[Errno 2] No
  # such file or directory: 'test'", after minutes of otherwise-
  # successful work. --setenv carries this script's PATH through.
  systemd-run --unit=sapohub-deploy --collect --no-block \
    --setenv=PATH="$PATH" \
    --setenv=FLAKE_PATH="$FLAKE_PATH" \
    --setenv=FLAKE_ATTR="$FLAKE_ATTR" \
    --setenv=STATUS_FILE="$STATUS_FILE" \
    ${runRebuild}

  # Stream the journal live for the browser terminal, but only for as
  # long as it takes the detached unit above to report a fresh result —
  # unlike before, this no longer runs forever. If sapohub.service (and
  # therefore this whole script) gets killed by the rebuild restarting
  # it, this loop just dies with it; the detached unit's status-file
  # write is unaffected and still lands, so "last deployed at" stays
  # correct even when the PTY session doesn't get to see the end.
  journalctl -u sapohub-deploy -f --no-pager &
  JPID=$!

  # 30 minutes of headroom for a full rebuild; the journal stream above
  # is the interesting output while this waits.
  i=0
  while [ "$i" -lt 1800 ]; do
    if [ -f "$STATUS_FILE" ] && [ "$STATUS_FILE" -nt "$MARKER" ]; then
      break
    fi
    sleep 1
    i=$((i + 1))
  done

  kill "$JPID" 2>/dev/null || true
  wait "$JPID" 2>/dev/null || true

  if [ -f "$STATUS_FILE" ] && [ "$STATUS_FILE" -nt "$MARKER" ]; then
    RESULT="$(grep -o '"status":"[a-z]*"' "$STATUS_FILE" | cut -d'"' -f4)"
    echo "deploy finished: $RESULT"
    [ "$RESULT" = "success" ]
  else
    echo "deploy did not report a result in time — check 'systemctl status sapohub-deploy'" >&2
    exit 1
  fi
''
