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
the same `modules` binding as its `nixosModules.default`.

If you'd rather splice the pieces by hand instead of importing the
module (e.g. to reorder relative to other modules), `sapohubModulesForHost`
is exposed too — it's the same list `nixosModules.default` imports.

UI preferences: the template's `prefsImport` — a conditional import of
`.sapohub/sapohub-prefs.nix`, the file the Settings page's Deploy button
syncs preferences into — is already wired into `sapohubModulesForHost`.
Nix can't auto-detect this file for you (an `imports` list has to resolve
before any config value exists), so keep that line if you fork this
template into your own repo. No stub file needs to exist up front —
`pathExists` just skips it until the first sync.

The recommended networking options for an existing box are Tailscale +
HTTPS nginx — add them alongside `deploy.flakeAttr`:

```nix
{ services.sapohub.deploy.flakeAttr = "<your-host>";
  services.sapohub.tailscale.enable = true;
  services.sapohub.nginx.https = true; }
```

`tailscale.enable` installs and starts tailscaled (you still need to run
`tailscale up` once to authenticate if you don't supply an auth key).
`nginx.https = true` enables the nginx reverse proxy on port 443 with
Tailscale-issued TLS certificates — without it nginx only listens on
port 80 and the firewall stays closed.

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
