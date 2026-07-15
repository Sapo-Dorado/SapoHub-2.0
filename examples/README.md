# Deploying SapoHub

There are two ways to run SapoHub, depending on whether you're starting
from a wiped/fresh machine or already have a NixOS box you manage.

## Fresh machine (no existing NixOS config)

Use `./scripts/bootstrap.sh <ip>` from the repo root. It targets
`nixosConfigurations.fresh-machine` in the root `flake.nix` — a
Tailscale-only host (no public ACME/firewall; nginx fronts the app on
port 80 by default) with a disko disk layout and `services.sapohub`
already wired up. Works on hardware you
haven't described to Nix in advance: the script has nixos-anywhere
generate the target's `hardware-configuration.nix` and figure out the
disk device for you, rather than requiring you to hand-write either one
up front.

See the README.md "Fresh machine" section for the full walkthrough
(secrets seeding, Tailscale auth key, what to do if something fails
partway through).

Nothing in `examples/` is needed for this path.

## Existing NixOS box (you already have a config)

See `examples/user-config/flake.nix`. It's a template for your own
personal config repo: `modules`, `depsHash`/`npmDepsHash`, and `prefs`
are each defined once and referenced everywhere they're needed, and it
exposes its own `nixosModules.default` — so adding SapoHub to an
existing `nixosConfigurations.<your-host>` is just importing that one
module plus setting `services.sapohub.deploy.flakeAttr` (the one value
that can't have a universal default, since it's whatever you call your
own host). It deliberately does not assume anything about your disks,
filesystems, bootloader, or hardware config, because those are already
yours.

[SapoHub-Config](https://github.com/Sapo-Dorado/SapoHub-Config) is a
real, deployed instance built the same way — worth reading alongside
this example, since it also shows the fresh-machine side (its own
`nixosConfigurations.<host>` via `sapohub.lib.mkFreshMachine`) sharing
the same `modules`/`prefs` bindings as its `nixosModules.default`.

If you'd rather splice the pieces by hand instead of importing the
module (e.g. to omit `sapohub-prefs.nix`, or reorder relative to other
modules), `sapohubModulesForHost` is exposed too — it's the same list
`nixosModules.default` imports.

Copy `examples/user-config/sapohub-prefs.nix` alongside your own
`flake.nix` too — it's a machine-owned file that the Settings page's
Deploy button (or `sapohub-deploy --sync-prefs`) writes UI preferences
into, and it needs to exist (even empty) before the first
`nixos-rebuild switch`.

Before running `nixos-rebuild switch`, create the secrets file on the
target machine (the bootstrap script does this automatically for the
fresh-machine path, but for an existing box you do it once by hand):

```sh
sudo mkdir -p /etc/sapohub
sudo sh -c 'echo "SECRET_KEY_BASE=$(openssl rand -hex 64)" > /etc/sapohub/secrets.env'
sudo chmod 600 /etc/sapohub/secrets.env
```

The service will not start correctly without `SECRET_KEY_BASE`. Any
other secrets (e.g. `GITHUB_TOKEN`) can be added to the same file later
via `sapohub-set-secret` or the Settings UI.
