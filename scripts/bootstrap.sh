#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a fresh machine into a running SapoHub install via nixos-anywhere.
#
# Repo-agnostic: works against THIS repo's own nixosConfigurations.fresh-
# machine example, or against a personal config repo (e.g. one built from
# examples/user-config/) that defines its own hosts via
# `sapohub.lib.mkFreshMachine` — pass --flake-path to point it elsewhere.
#
# Convention this script and lib.mkFreshMachine both rely on: the
# nixosConfigurations attribute name IS the hostname IS the prefix for
# that host's generated hardware files (hardware/<hostname>-hardware-
# configuration.nix, hardware/<hostname>-disk-device.nix). This is what
# lets ONE config repo bootstrap several distinct machines over time
# without one host's hardware config clobbering another's — --hostname
# selects both which nixosConfigurations attribute to build AND which
# generated-file pair to read/write.
#
# The target machine needs to already be reachable over SSH as root and
# booted into SOME NixOS-based environment (the official installer ISO,
# or an existing NixOS install you're willing to wipe) — nixos-anywhere
# does the rest: partitions the disk (disko), builds the closure, and
# switches the target over to it, typically rebooting once along the way.
#
# Usage:
#   ./scripts/bootstrap.sh <ip> --hostname <name> [options]
#
# Options:
#   --hostname <name>          REQUIRED. Names this machine — becomes the
#                              nixosConfigurations attribute built, AND the
#                              prefix for its generated hardware files
#                              (hardware/<name>-hardware-configuration.nix,
#                              hardware/<name>-disk-device.nix). Pick
#                              something stable; you'll reuse it for every
#                              future bootstrap/rebuild of THIS machine.
#   --flake-path <path>        Path to the config repo to build from
#                              (default: this script's own repo). Point
#                              this at your personal config repo if you
#                              have one — the flake there needs a
#                              `nixosConfigurations.<hostname>` output
#                              (typically built via `sapohub.lib.
#                              mkFreshMachine { hostname = "..."; ... }`).
#   --disk <device>            Target disk device to partition, e.g. /dev/sda,
#                              /dev/vda, /dev/nvme0n1 (default: /dev/sda —
#                              CHANGE THIS if your machine's primary disk is
#                              anything else; get it from `lsblk` over SSH
#                              if unsure).
#   --ssh-user <user>          SSH user on the target (default: root).
#   --secrets-file <path>      Local path to a prepared secrets.env
#                              (SECRET_KEY_BASE=...) to seed onto the target
#                              BEFORE first boot, so sapohub.service doesn't
#                              crash-loop waiting on it. If omitted, one is
#                              generated for you and printed at the end —
#                              it's already seeded either way.
#   --tailscale-auth-key-file <path>
#                              Local path to a file containing a Tailscale
#                              auth key, seeded onto the target so it joins
#                              your tailnet unattended on first boot. If
#                              omitted, you'll need to run `tailscale up` by
#                              hand over the (still-open, since SSH isn't
#                              Tailscale-gated) root SSH session afterward.
#   --no-commit                Skip committing/pushing the generated
#                              hardware files into --flake-path after a
#                              successful install (default: commit + push
#                              automatically — see "Hardware config
#                              persistence" below). Use this if you'd
#                              rather review the generated files by hand
#                              first.
#
# What actually makes this work on arbitrary hardware:
#   1. --generate-hardware-config: nixos-anywhere SSHes into the target,
#      runs `nixos-generate-config` THERE, and copies the result back to
#      <flake-path>/hardware/<hostname>-hardware-configuration.nix on this
#      machine — which lib.mkFreshMachine picks up automatically once it
#      exists (falling back to hardware/example-hardware-configuration.nix
#      otherwise, e.g. before the first bootstrap of a given hostname).
#   2. --extra-files: seeds /etc/sapohub/secrets.env (and, if provided,
#      /etc/sapohub/tailscale-authkey) into the target's filesystem BEFORE
#      the first activation, so the service has what it needs the moment
#      it starts rather than crash-looping until someone SSHes in by hand.
# Both are standard nixos-anywhere flags — nothing custom.
#
# Hardware config persistence: nixos-anywhere generates this machine's
# hardware-configuration.nix and disk device LOCALLY, on whatever machine
# runs this script — not on the target. Left uncommitted, that config
# would only ever exist on your local disk: the target's own
# /etc/sapohub-config checkout (seeded below, for future `sapohub-deploy`
# redeploys) wouldn't have it, and the next redeploy would silently fall
# back to the generic placeholder — wrong kernel modules, wrong disk
# device. So by default (unless --no-commit) this script commits the two
# generated files into --flake-path and pushes, right after a successful
# install, before seeding the target's own checkout — so that checkout
# already has the real thing.

SCRIPT_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET_IP=""
HOSTNAME_ARG=""
FLAKE_PATH="$SCRIPT_REPO_ROOT"
DISK_DEVICE="/dev/sda"
SSH_USER="root"
SECRETS_FILE=""
TS_AUTH_KEY_FILE=""
NO_COMMIT=""

usage() {
  echo "usage: $0 <ip> --hostname <name> [--flake-path <path>] [--disk <device>] [--ssh-user <user>] [--secrets-file <path>] [--tailscale-auth-key-file <path>] [--no-commit]" >&2
  exit 1
}

[ $# -ge 1 ] || usage
TARGET_IP="$1"; shift

while [ $# -gt 0 ]; do
  case "$1" in
    --hostname) HOSTNAME_ARG="$2"; shift 2 ;;
    --flake-path) FLAKE_PATH="$(cd "$2" && pwd)"; shift 2 ;;
    --disk) DISK_DEVICE="$2"; shift 2 ;;
    --ssh-user) SSH_USER="$2"; shift 2 ;;
    --secrets-file) SECRETS_FILE="$2"; shift 2 ;;
    --tailscale-auth-key-file) TS_AUTH_KEY_FILE="$2"; shift 2 ;;
    --no-commit) NO_COMMIT="1"; shift ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done

[ -n "$HOSTNAME_ARG" ] || { echo "--hostname is required — see the header comment for why." >&2; usage; }

echo "== SapoHub fresh-machine bootstrap =="
echo "target:        ${SSH_USER}@${TARGET_IP}"
echo "hostname:      ${HOSTNAME_ARG}"
echo "flake path:    ${FLAKE_PATH}"
echo "disk device:   ${DISK_DEVICE}"
echo ""

HW_DIR="$FLAKE_PATH/hardware"
mkdir -p "$HW_DIR"
GENERATED_HW_CONFIG="$HW_DIR/${HOSTNAME_ARG}-hardware-configuration.nix"
GENERATED_DISK_DEVICE="$HW_DIR/${HOSTNAME_ARG}-disk-device.nix"

# ---- 1. Disk device: written per-hostname so multiple hosts can coexist ----
cat > "$GENERATED_DISK_DEVICE" <<NIXEOF
{
  sapohubDiskDevice = "${DISK_DEVICE}";
}
NIXEOF
echo "wrote $(basename "$GENERATED_DISK_DEVICE") (${DISK_DEVICE})"

# ---- 2. Secrets: generate one if the caller didn't bring their own ----
EXTRA_FILES_DIR="$(mktemp -d)"
trap 'rm -rf "$EXTRA_FILES_DIR"' EXIT

mkdir -p "$EXTRA_FILES_DIR/etc/sapohub"
GENERATED_SECRET=""
if [ -n "$SECRETS_FILE" ]; then
  [ -f "$SECRETS_FILE" ] || { echo "--secrets-file not found: $SECRETS_FILE" >&2; exit 1; }
  cp "$SECRETS_FILE" "$EXTRA_FILES_DIR/etc/sapohub/secrets.env"
else
  GENERATED_SECRET="$(head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  echo "SECRET_KEY_BASE=${GENERATED_SECRET}" > "$EXTRA_FILES_DIR/etc/sapohub/secrets.env"
  echo "no --secrets-file given — generated a fresh SECRET_KEY_BASE"
fi
chmod 600 "$EXTRA_FILES_DIR/etc/sapohub/secrets.env"

if [ -n "$TS_AUTH_KEY_FILE" ]; then
  [ -f "$TS_AUTH_KEY_FILE" ] || { echo "--tailscale-auth-key-file not found: $TS_AUTH_KEY_FILE" >&2; exit 1; }
  cp "$TS_AUTH_KEY_FILE" "$EXTRA_FILES_DIR/etc/sapohub/tailscale-authkey"
  chmod 600 "$EXTRA_FILES_DIR/etc/sapohub/tailscale-authkey"
  echo "seeding Tailscale auth key — machine will join your tailnet on first boot"
else
  echo "no --tailscale-auth-key-file given — you'll need to run 'tailscale up' on the box yourself after bootstrap"
fi

echo ""
echo "starting nixos-anywhere (this partitions ${DISK_DEVICE} on ${TARGET_IP} — DESTRUCTIVE, double-check the IP and disk device now)..."
echo ""
read -r -p "Type the target IP again to confirm (${TARGET_IP}): " CONFIRM_IP
if [ "$CONFIRM_IP" != "$TARGET_IP" ]; then
  echo "confirmation didn't match — aborting, nothing was touched." >&2
  exit 1
fi

nix run github:nix-community/nixos-anywhere -- \
  --flake "${FLAKE_PATH}#${HOSTNAME_ARG}" \
  --generate-hardware-config nixos-generate-config "$GENERATED_HW_CONFIG" \
  --extra-files "$EXTRA_FILES_DIR" \
  "${SSH_USER}@${TARGET_IP}"

# ---- 3. Persist the generated hardware config into the config repo ----
# (see the "Hardware config persistence" header comment for why this
# matters — without it, only your local disk has the real hardware
# config, and the target's own checkout would silently fall back to the
# generic placeholder on the next redeploy.)
if [ -z "$NO_COMMIT" ]; then
  if git -C "$FLAKE_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo ""
    echo "committing generated hardware config for '${HOSTNAME_ARG}' into ${FLAKE_PATH} ..."
    git -C "$FLAKE_PATH" add \
      "hardware/${HOSTNAME_ARG}-hardware-configuration.nix" \
      "hardware/${HOSTNAME_ARG}-disk-device.nix"
    if ! git -C "$FLAKE_PATH" diff --cached --quiet; then
      git -C "$FLAKE_PATH" commit -m "hardware: generated config for ${HOSTNAME_ARG}"
      if git -C "$FLAKE_PATH" remote get-url origin >/dev/null 2>&1; then
        git -C "$FLAKE_PATH" push
        echo "pushed."
      else
        echo "committed locally — no 'origin' remote to push to, push it yourself when ready."
      fi
    else
      echo "nothing to commit (unchanged from a previous run for this hostname)."
    fi
  else
    echo ""
    echo "NOTE: ${FLAKE_PATH} isn't a git repo — couldn't commit the generated hardware config."
    echo "It's still on local disk at hardware/${HOSTNAME_ARG}-{hardware-configuration,disk-device}.nix; commit it yourself."
  fi
else
  echo ""
  echo "--no-commit passed — generated hardware config left uncommitted at hardware/${HOSTNAME_ARG}-{hardware-configuration,disk-device}.nix"
fi

# ---- 4. Give the target a git checkout at deploy.flakePath ----
# nixos-anywhere builds+activates the closure FROM this local checkout
# over SSH; it doesn't leave a git checkout on the target itself. But
# services.sapohub.deploy.flakePath needs one to exist there for FUTURE
# `sapohub-deploy` redeploys to have something to `git pull` and rebuild
# from. Clone --flake-path's own origin onto the target now, once it's
# reachable again post-install.
ORIGIN_URL="$(git -C "$FLAKE_PATH" remote get-url origin 2>/dev/null || true)"
if [ -n "$ORIGIN_URL" ]; then
  echo ""
  echo "waiting for the target to come back up after install..."
  # The target reboots from the temporary kexec-installer environment into
  # its real, final NixOS system — which generates its own permanent host
  # key, different from whatever ephemeral key the installer environment
  # was using. That's an EXPECTED key change, not tampering, but ssh (even
  # with StrictHostKeyChecking=accept-new, which only auto-trusts hosts it
  # has never seen before) will refuse to reconnect once an entry exists
  # and looks different. Drop any entry recorded during the kexec/install
  # phases now, so the reconnect below gets a clean accept-new instead of
  # silently failing every retry and only surfacing as a confusing error
  # later, at the git clone step.
  ssh-keygen -R "$TARGET_IP" >/dev/null 2>&1 || true
  RECONNECTED=""
  for _ in $(seq 1 30); do
    if ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "${SSH_USER}@${TARGET_IP}" true 2>/dev/null; then
      RECONNECTED="1"
      break
    fi
    sleep 5
  done
  if [ -z "$RECONNECTED" ]; then
    echo "NOTE: couldn't reconnect to ${TARGET_IP} after reboot within 150s — it may still be coming up." >&2
    echo "sapohub-deploy (future redeploys) expects a git checkout at /etc/sapohub-config — seed it by hand once it's reachable:" >&2
    echo "  ssh ${SSH_USER}@${TARGET_IP} git clone <your-repo-url> /etc/sapohub-config" >&2
  else
    # Cloning happens ON THE TARGET, using the target's own credentials —
    # which, unlike this machine, it doesn't have any of. An SSH-form
    # GitHub URL (git@github.com:owner/repo) would need a deploy key we
    # never provisioned, and would also hit the same "new host, unknown
    # key" friction against github.com's host key from the target's own
    # known_hosts (empty, fresh machine). Rewrite it to HTTPS when
    # possible so the clone doesn't need any credentials or host-key trust
    # at all — this works as long as the repo is public; bring your own
    # credentials on the target if it's private.
    CLONE_URL="$ORIGIN_URL"
    case "$ORIGIN_URL" in
      git@github.com:*)
        CLONE_URL="https://github.com/${ORIGIN_URL#git@github.com:}" ;;
      ssh://git@github.com/*)
        CLONE_URL="https://github.com/${ORIGIN_URL#ssh://git@github.com/}" ;;
    esac
    echo "cloning ${CLONE_URL} to /etc/sapohub-config on the target (for future sapohub-deploy redeploys)..."
    if ! ssh -o StrictHostKeyChecking=accept-new "${SSH_USER}@${TARGET_IP}" \
      "nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#git -c git clone '${CLONE_URL}' /etc/sapohub-config"; then
      echo "NOTE: clone failed on the target (private repo without credentials there? wrong URL?)." >&2
      echo "sapohub-deploy (future redeploys) expects a git checkout at /etc/sapohub-config — seed it by hand:" >&2
      echo "  ssh ${SSH_USER}@${TARGET_IP} git clone <your-repo-url> /etc/sapohub-config" >&2
    fi
  fi
else
  echo ""
  echo "NOTE: ${FLAKE_PATH} has no 'origin' remote, so I couldn't seed /etc/sapohub-config on the target automatically."
  echo "sapohub-deploy (future redeploys) expects a git checkout there — clone your config repo to it by hand:"
  echo "  ssh ${SSH_USER}@${TARGET_IP} git clone <your-repo-url> /etc/sapohub-config"
fi

echo ""
echo "== bootstrap complete =="
if [ -n "$GENERATED_SECRET" ]; then
  echo "generated SECRET_KEY_BASE (already seeded onto the target, saved here in case you need it): ${GENERATED_SECRET}"
fi
echo "SapoHub should be reachable shortly at http://<tailscale-hostname>:4000 once the machine joins your tailnet."
echo "Future updates: ssh ${SSH_USER}@${TARGET_IP}, then run 'sapohub-deploy' (or use the Settings page's Deploy button — see README)."
echo "Future bootstraps/rebuilds of THIS machine should reuse --hostname ${HOSTNAME_ARG} — that's how its hardware config gets found again."
