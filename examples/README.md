# Deploying SapoHub

There are two ways to run SapoHub, depending on whether you're starting
from a wiped/fresh machine or already have a NixOS box you manage.

## Fresh machine (no existing NixOS config)

Use `./scripts/bootstrap.sh <ip>` from the repo root. It targets
`nixosConfigurations.fresh-machine` in the root `flake.nix` — a
Tailscale-only host (no public nginx/ACME/firewall) with a disko disk
layout and `services.sapohub` already wired up. Works on hardware you
haven't described to Nix in advance: the script has nixos-anywhere
generate the target's `hardware-configuration.nix` and figure out the
disk device for you, rather than requiring you to hand-write either one
up front.

See the README.md "Fresh machine" section for the full walkthrough
(secrets seeding, Tailscale auth key, what to do if something fails
partway through).

Nothing in `examples/` is needed for this path.

## Existing NixOS box (you already have a config)

See `examples/user-config/flake.nix`. It shows exactly what to add to
your **own** existing `nixosConfigurations.<your-host>` — the flake
input, `sapohub.nixosModules.default`, and a `services.sapohub = {...}`
block — without assuming anything about your disks, filesystems,
bootloader, or hardware config, because those are already yours. Don't
treat that file as something to `nixos-rebuild switch` against directly;
splice its `sapohubModulesForHost` list into your own config's `modules`.

Copy `examples/user-config/sapohub-prefs.nix` alongside your own
`flake.nix` too — it's a machine-owned file that the Settings page's
Deploy button (or `sapohub-deploy --sync-prefs`) writes UI preferences
into, and it needs to exist (even empty) before the first
`nixos-rebuild switch`.
