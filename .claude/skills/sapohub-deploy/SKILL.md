---
name: sapohub-deploy
description: >
  Deploys SapoHub 2.0 to a fresh machine via nixos-anywhere, or helps splice
  it into an existing NixOS config. Also covers customizing an install
  (module selection, dashboard/UI preferences, secrets, notification
  destinations, the assistant browser) and redeploying an already-running
  box. Use this whenever the user wants to stand up a new SapoHub instance,
  add it to hardware they already run NixOS on, or change how an existing
  install is configured.
user-invocable: true
argument-hint: "[fresh-machine <ip> | existing-config | redeploy | customize]"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# SapoHub Deploy

SapoHub 2.0 has exactly two ways to run: bootstrap a fresh machine from
scratch, or add the `services.sapohub` NixOS module to a config you
already own. Both end up at the same place — a `nixosConfigurations`
output with `services.sapohub` enabled — they just differ in whether YOU
or the bootstrap script own the disk/filesystem/bootloader config.

Read `README.md` and `examples/README.md` in the repo root first if
you haven't already; this skill assumes their content and won't repeat
all of it verbatim.

## Deciding which path applies

Ask (or infer from context) whether the target machine:
- Is wiped, or the user is willing to wipe it, and has no NixOS config
  you'd be building on top of → **fresh machine**.
- Already runs NixOS with an existing flake/config the user maintains →
  **existing config**.

If genuinely unclear, ask the user directly rather than guessing — the
fresh-machine path is destructive (it partitions a disk) and the wrong
guess here is expensive to undo.

## Path 1: fresh machine (nixos-anywhere)

Entry point: `./scripts/bootstrap.sh <ip> [options]` from the repo root.
Read the script itself (`scripts/bootstrap.sh`) before running it — it's
short, heavily commented, and the comments explain exactly what each
step does and why (hardware-config generation, disk device override,
secrets seeding via `--extra-files`, the post-install git clone that
seeds `/etc/sapohub-config` for future redeploys).

Preconditions to check with the user before running it:
1. The target is reachable over SSH as root right now (`ssh root@<ip>
   true` should succeed without a password prompt looping forever —
   NixOS installer ISOs default to no root password and often need an
   `authorized_keys` entry set via the installer's own tooling, or
   `passwd root` + password auth temporarily).
2. Which block device to partition (`ssh root@<ip> lsblk` — the script
   defaults to `/dev/sda`, override with `--disk`).
3. Whether they want to bring their own `SECRET_KEY_BASE`/secrets file
   (`--secrets-file`) or let the script generate one (default — printed
   at the end, already seeded onto the target either way).
4. Whether they have a Tailscale auth key to seed
   (`--tailscale-auth-key-file`) for unattended tailnet join, or would
   rather run `tailscale up` by hand after bootstrap.

The script asks for IP re-confirmation immediately before the
destructive nixos-anywhere run — don't route around that by scripting
the confirmation input; let the user actually see and confirm it.

**Customizing the fresh-machine target itself** (module selection,
`agentNotes`, `assistant.browser.enable`, etc.) means editing the
`nixosConfigurations.fresh-machine` block directly in the repo's root
`flake.nix` before running bootstrap.sh — it's the same
`services.sapohub = { ... }` shape documented in "Customizing an
install" below. If the user wants a fresh machine with a NON-default
module set or options, edit that block first.

If nixos-anywhere fails partway through (common: SSH key issues, wrong
disk device, target not actually in an installer environment), it's
usually safe to just fix the issue and re-run `bootstrap.sh` — disko
repartitions from scratch each time, and the hardware-config/disk-device
override files get regenerated fresh on every run.

## Path 2: existing NixOS config

Read `examples/user-config/flake.nix` in full — its header comment and
`sapohubModulesForHost` list are the actual content to work from. The
task is: help the user add `sapohub.nixosModules.default` plus a
`services.sapohub = { ... }` block into THEIR existing
`nixosConfigurations.<their-host>`'s `modules` list, without touching
their `fileSystems`, `boot.loader`, or hardware config.

Concretely, this means:
1. Read the user's existing flake.nix (ask for its path/contents if you
   don't already have access to it — it may live in a completely
   separate repo from SapoHub).
2. Add `sapohub` as a flake input (mirroring
   `examples/user-config/flake.nix`'s `inputs.sapohub.url`).
3. Add `sapohub.lib.mkSapoHub { ... }` to compute the package/cli,
   choosing their module set.
4. Append `sapohub.nixosModules.default`, a `./sapohub-prefs.nix` import
   (copy the empty-stub file from `examples/user-config/sapohub-prefs.nix`
   into their repo first — commit it before the first
   `nixos-rebuild switch`, not after), and the `services.sapohub = {...}`
   block into their EXISTING `nixosConfigurations.<host>`'s `modules`
   list — don't create a new nixosConfigurations output.
5. Point `deploy.flakePath` at wherever their config repo will live ON
   the target machine, and `deploy.flakeAttr` at their actual
   `nixosConfigurations` attribute name (not `"hub"` unless that's
   genuinely what they called it).
6. They run `nixos-rebuild switch --flake .#<their-attr>` themselves
   (or however they normally deploy their own config) — this skill
   doesn't run destructive commands against a machine you don't know
   the topology of.

## Customizing an install (either path)

All of this lives in the `services.sapohub = { ... }` block — read
`nix/nixos-module.nix`'s `options.services.sapohub` for the authoritative,
current list (don't rely on memory of it; module options can change).
As of this writing, the pieces worth knowing:

- **Module selection**: the `modules` list passed to
  `sapohub.lib.mkSapoHub` — any `sapohubModules.<name>` from this repo,
  or `inputs.<their-flake>.sapohubModule` for an external module. Adding
  or removing a module changes `depsHash`/`npmDepsHash` — nix's error
  message on a hash mismatch prints the correct value; paste it in.
- **Dashboard/UI preferences** (`services.sapohub.prefs`): dashboard
  tile order, button variants, statusline toggles. Normally NOT
  hand-edited — set live in the Settings UI, then synced to
  `sapohub-prefs.nix` by the Settings page's Deploy button
  (`sapohub-deploy --sync-prefs`). A bare `sapohub-deploy` (SSH, cron,
  anywhere outside the UI) never does this sync, by design — git/nix
  stays authoritative unless the user explicitly deploys from the UI.
- **Secrets** (`secretsFile`): a root-owned env file, `SECRET_KEY_BASE=`
  plus any module-specific secrets. Check the module's own docs for what
  else it expects there (e.g. a bot token) — this skill doesn't track
  per-module secret requirements, they do.
- **Notification destinations**: configured at runtime through the app's
  own Settings UI (Telegram, etc.), not through nix — nothing to set in
  the flake for this.
- **Assistant** (`assistant.claudePackage`, `assistant.workDir`,
  `assistant.browser.enable`): `claudePackage` needs the unfree
  `claude-code-nix` overlay applied to the `pkgs` used for that value —
  see how `nixosConfigurations.fresh-machine` in the root `flake.nix`
  does it (`import nixpkgs { config.allowUnfree = true; overlays = [
  claude-code-nix.overlays.default ]; }`) if the user's own config
  doesn't already have unfree packages allowed. `browser.enable` turns on
  a persistent Xvfb + Chrome pair for assistant sessions/skills that need
  a real browser (heavier; only enable if actually needed).

## Redeploying an already-running box

`sapohub-deploy` is installed on the target (via `environment.systemPackages`
in the module) and is the one thing the restricted sudoers rule allows.
SSH in and run it directly, or use the Settings page's Deploy button (adds
`--sync-prefs`). `nix/deploy-script.nix` is the actual implementation if
you need to understand exactly what it does — it's short and heavily
commented; read it rather than guessing at its behavior.

## What NOT to do

- Don't invent a disk layout, hardware config, or bootloader setting for
  an existing-config user — that's real, already-working config on their
  machine; changing it wrong can leave a box unbootable.
- Don't run `scripts/bootstrap.sh` or any nixos-anywhere invocation
  without the user explicitly confirming the target IP and that
  destroying the target's current disk contents is intended.
- Don't hand-write `sapohub-prefs.nix` content for a user — it's
  machine-owned and meant to be synced from the running app's Settings
  page, not authored directly (the only exception is the initial empty
  stub, which is fine to copy verbatim).
