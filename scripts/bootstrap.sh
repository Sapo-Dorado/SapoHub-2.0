#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a fresh machine into a running SapoHub install via nixos-anywhere.
#
# Targets the `fresh-machine` nixosConfigurations output in this repo's
# flake.nix — a Tailscale-only, no-public-exposure host config (disko disk
# layout + services.sapohub). Works on hardware you haven't described to
# Nix in advance: the disk device and the hardware-configuration.nix are
# both figured out FROM the target machine at bootstrap time, not
# hardcoded — see the two mechanisms below.
#
# The target machine needs to already be reachable over SSH as root and
# booted into SOME NixOS-based environment (the official installer ISO,
# or an existing NixOS install you're willing to wipe) — nixos-anywhere
# does the rest: partitions the disk (disko), builds the closure, and
# switches the target over to it, typically rebooting once along the way.
#
# Usage:
#   ./scripts/bootstrap.sh <ip> [options]
#
# Options:
#   --disk <device>           Target disk device to partition, e.g. /dev/sda,
#                              /dev/vda, /dev/nvme0n1 (default: /dev/sda —
#                              CHANGE THIS if your machine's primary disk is
#                              anything else; get it from `lsblk` over SSH
#                              if unsure).
#   --ssh-user <user>          SSH user on the target (default: root).
#   --flake-attr <attr>        nixosConfigurations attribute to deploy
#                              (default: fresh-machine).
#   --secrets-file <path>      Local path to a prepared secrets.env
#                              (SECRET_KEY_BASE=...) to seed onto the target
#                              BEFORE first boot, so sapohub.service doesn't
#                              crash-loop waiting on it. If omitted, one is
#                              generated for you and printed at the end —
#                              you MUST copy it to /etc/sapohub/secrets.env
#                              on the target yourself before the service can
#                              start.
#   --tailscale-auth-key-file <path>
#                              Local path to a file containing a Tailscale
#                              auth key, seeded onto the target so it joins
#                              your tailnet unattended on first boot. If
#                              omitted, you'll need to run `tailscale up` by
#                              hand over the (still-open, since SSH isn't
#                              Tailscale-gated) root SSH session afterward.
#
# What actually makes this work on arbitrary hardware:
#   1. --generate-hardware-config: nixos-anywhere SSHes into the target,
#      runs `nixos-generate-config` THERE, and copies the result back to
#      hardware/generated-hardware-configuration.nix on this machine —
#      which the flake imports automatically once it exists (see the
#      fresh-machine nixosConfigurations block and
#      hardware/example-hardware-configuration.nix's header comment).
#   2. --extra-files: seeds /etc/sapohub/secrets.env (and, if provided,
#      /etc/sapohub/tailscale-authkey) into the target's filesystem BEFORE
#      the first activation, so the service has what it needs the moment
#      it starts rather than crash-looping until someone SSHes in by hand.
#
# Both of these are standard nixos-anywhere flags — nothing custom.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TARGET_IP=""
DISK_DEVICE="/dev/sda"
SSH_USER="root"
FLAKE_ATTR="fresh-machine"
SECRETS_FILE=""
TS_AUTH_KEY_FILE=""

usage() {
  echo "usage: $0 <ip> [--disk <device>] [--ssh-user <user>] [--flake-attr <attr>] [--secrets-file <path>] [--tailscale-auth-key-file <path>]" >&2
  exit 1
}

[ $# -ge 1 ] || usage
TARGET_IP="$1"; shift

while [ $# -gt 0 ]; do
  case "$1" in
    --disk) DISK_DEVICE="$2"; shift 2 ;;
    --ssh-user) SSH_USER="$2"; shift 2 ;;
    --flake-attr) FLAKE_ATTR="$2"; shift 2 ;;
    --secrets-file) SECRETS_FILE="$2"; shift 2 ;;
    --tailscale-auth-key-file) TS_AUTH_KEY_FILE="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done

echo "== SapoHub fresh-machine bootstrap =="
echo "target:        ${SSH_USER}@${TARGET_IP}"
echo "disk device:   ${DISK_DEVICE}"
echo "flake attr:    ${FLAKE_ATTR}"
echo ""

# ---- 1. Disk device: written to a gitignored override the flake reads ----
# (nix/disko-config.nix imports hardware/generated-disk-device.nix if it
# exists, falling back to hardware/example-disk-device.nix's /dev/sda.)
cat > "$REPO_ROOT/hardware/generated-disk-device.nix" <<NIXEOF
{
  sapohubDiskDevice = "${DISK_DEVICE}";
}
NIXEOF
echo "wrote hardware/generated-disk-device.nix (${DISK_DEVICE})"

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
  --flake "${REPO_ROOT}#${FLAKE_ATTR}" \
  --generate-hardware-config nixos-generate-config "${REPO_ROOT}/hardware/generated-hardware-configuration.nix" \
  --extra-files "$EXTRA_FILES_DIR" \
  "${SSH_USER}@${TARGET_IP}"

# ---- 3. Give the target a git checkout at deploy.flakePath ----
# nixos-anywhere builds+activates the closure FROM this local checkout over
# SSH; it doesn't leave a git checkout on the target itself. But
# services.sapohub.deploy.flakePath (fresh-machine's nixosConfigurations
# block sets it to /etc/sapohub-config) needs one to exist there for FUTURE
# `sapohub-deploy` redeploys to have something to `git pull` and rebuild
# from. Clone this repo's own origin onto the target now, once it's
# reachable again post-install, so redeploys work immediately without a
# manual step.
ORIGIN_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
if [ -n "$ORIGIN_URL" ]; then
  echo ""
  echo "waiting for the target to come back up after install..."
  for _ in $(seq 1 30); do
    ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "${SSH_USER}@${TARGET_IP}" true 2>/dev/null && break
    sleep 5
  done
  echo "cloning ${ORIGIN_URL} to /etc/sapohub-config on the target (for future sapohub-deploy redeploys)..."
  ssh -o StrictHostKeyChecking=accept-new "${SSH_USER}@${TARGET_IP}" \
    "git clone '${ORIGIN_URL}' /etc/sapohub-config 2>&1 || echo 'clone failed — see below'"
else
  echo ""
  echo "NOTE: this checkout has no 'origin' remote, so I couldn't seed /etc/sapohub-config on the target automatically."
  echo "sapohub-deploy (future redeploys) expects a git checkout there — clone your config repo to it by hand:"
  echo "  ssh ${SSH_USER}@${TARGET_IP} git clone <your-repo-url> /etc/sapohub-config"
fi

echo ""
echo "== bootstrap complete =="
if [ -n "$GENERATED_SECRET" ]; then
  echo "generated SECRET_KEY_BASE (already seeded onto the target, saved here in case you need it): ${GENERATED_SECRET}"
fi
echo "hardware/generated-hardware-configuration.nix and hardware/generated-disk-device.nix were written locally by this run — commit them if you want this exact machine reproducible from git, or leave them gitignored and re-run bootstrap.sh again next time (they'll be regenerated fresh)."
echo "SapoHub should be reachable shortly at http://<tailscale-hostname>:4000 once the machine joins your tailnet."
echo "Future updates: ssh ${SSH_USER}@${TARGET_IP}, then run 'sapohub-deploy' (or use the Settings page's Deploy button — see README)."
