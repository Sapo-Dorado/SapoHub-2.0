# SapoHub 2.0

A personal utility hub, rebuilt as an extensible, Nix-composed platform.
Phoenix LiveView + SQLite. One nix config, one deploy command, pluggable
"utility modules", an embedded Claude assistant, and a single "Save all
data" snapshot covering everything.

**Design in one paragraph**: utility modules are completely independent of
each other — anything more than one module needs (notifications, storage,
scheduling, HTTP) is a CORE service reached through `SapoKit.*` facades.
Modules are ordinary Mix projects with exactly one dependency (the
`sapo_module_kit` contract); Nix composes the enabled set into one release,
one `sapo` CLI, and one NixOS service. The app runs without root except
for exactly one sudo command: `sapohub-deploy`.

## Layout

```
contract/    :sapo_module_kit — the module contract + SapoKit.* facades
core/        :sapo_core — the Phoenix app (dashboard, assistant, settings,
             scheduler, notify, storage, snapshots, AI context, CLI core)
modules/     in-repo utility modules (hello = reference, my_plate = tasks)
nix/         compose.nix, cli.nix, nixos-module.nix, deploy-script.nix
hardware/    example-hardware-configuration.nix, example-disk-device.nix —
             fallback placeholders; scripts/bootstrap.sh generates
             hardware/<hostname>-{hardware-configuration,disk-device}.nix
             per machine and commits them (see lib.mkFreshMachine)
scripts/     bootstrap.sh — fresh-machine deploy via nixos-anywhere
examples/    user-config/flake.nix — splice SapoHub into an EXISTING config
docs/        module-authoring.md — how to build a utility module
```

## Development

```sh
nix develop                # elixir, node, sqlite, tailwind4, jq, patched PTY helpers
cd core
mix setup                  # deps, db, migrations, assets
PORT=4001 mix phx.server   # port 4000 is production v1 on this machine
mix test
mix sapo.gen.cli           # assemble the sapo CLI at _build/dev/sapo
```

The dev module set lives in `core/config/modules.lock.exs` +
`core/lib/sapo_core/generated/registry.ex` (keep in sync; nix regenerates
both in releases). Scaffold a new module with `mix sapo.gen.module <name>`.

## Deployment

There are two starting points — see `examples/README.md` for the full
comparison. Short version:

### Fresh machine (nixos-anywhere)

No existing NixOS config, starting from a wiped box (or one you're
willing to wipe) that's reachable over SSH as root, booted into any
NixOS-based environment (the official installer ISO works fine):

```sh
./scripts/bootstrap.sh <ip> --hostname <name>
```

`--hostname` is required and matters beyond naming: it's both the
`nixosConfigurations` attribute built (this repo's own `fresh-machine`
example by default — pass `--flake-path` to target a personal config
repo instead, see `examples/README.md`) and the prefix for that specific
machine's generated hardware files
(`hardware/<hostname>-hardware-configuration.nix`,
`hardware/<hostname>-disk-device.nix`) — reuse the same `--hostname` on
every future bootstrap/rebuild of THIS machine, and pick a new one for a
different machine, so multiple hosts can share one config repo without
clobbering each other's hardware config.

Result is Tailscale-only (no public ACME/firewall; reachable at
`http://<tailscale-hostname>` once it joins your tailnet — nginx fronts
the app on port 80 by default, `services.sapohub.nginx.enable`; the app
itself still listens directly on `:4000` too), disko disk layout,
`services.sapohub` pre-wired. It works on hardware you
haven't described to Nix in advance: nixos-anywhere SSHes into the
target, runs `nixos-generate-config` there, and copies the result back
locally before building — you don't hand-write a hardware config or know
the exact kernel modules up front. You do need to know (or check via
`ssh root@<ip> lsblk`) which block device to partition; pass it with
`--disk /dev/whatever` if it isn't `/dev/sda`.

The script commits (and pushes, unless you pass `--no-commit`) the
generated hardware files into the config repo right after a successful
install — without that, only your local disk would have the real
hardware config, and the target's own checkout (seeded next, for future
redeploys) would silently fall back to the generic placeholder.

**Secrets**: by default the script generates a fresh `SECRET_KEY_BASE`
and seeds it onto the target via nixos-anywhere's `--extra-files`
mechanism *before* first boot, so `sapohub.service` has what it needs
the moment it starts instead of crash-looping until someone SSHes in.
Pass `--secrets-file <path>` to bring your own instead (useful once you
have module secrets beyond just `SECRET_KEY_BASE` — Telegram bot tokens,
etc. — see each module's docs for what it expects in that file).

One core (non-module) secret worth knowing about: `GITHUB_TOKEN`,
optional, used only by `sapohub-deploy --sync-prefs` (the Settings
page's Deploy button) to push the config-repo commit it makes when
syncing UI preferences back into git. Without it, that commit still
happens locally, it just can't push — the Settings page's Secrets
table flags it "missing" and disables Deploy until it's set. Generate
a **fine-grained personal access token** (not classic — classic tokens
are all-or-nothing across every repo you can access, more than this
needs):

1. GitHub → Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token
2. **Repository access**: "Only select repositories" → your config
   repo (e.g. `SapoHub-Config`) — nothing else
3. **Permissions**: Repository permissions → **Contents: Read and
   write** (this alone is enough to `git push`; leave everything else
   at "No access")
4. Add an expiration you're comfortable renewing on

Add it to the secrets file as `GITHUB_TOKEN=<token>`, same as any other
line in that file (root-only, never committed, never in the Nix
store).

**Tailscale**: pass `--tailscale-auth-key-file <path>` (a file containing
a Tailscale auth key) to have the machine join your tailnet unattended on
first boot. Without it, SSH in after bootstrap and run `tailscale up`
yourself — the root SSH session bootstrap.sh used stays valid either way,
since SSH isn't gated behind Tailscale.

The script always asks you to re-type the target IP as a last
confirmation before running nixos-anywhere — it's destructive (it
partitions the disk), and there's no undo.

**After bootstrap**: it clones this repo's own `origin` remote onto the
target at `/etc/sapohub-config` (what `services.sapohub.deploy.flakePath`
points at), so future updates work immediately — `ssh <ip>`, then
`sapohub-deploy`, or the Settings page's Deploy button.

### Existing NixOS box

Already manage a NixOS config? Write one flake (see
`examples/user-config/flake.nix`): pick modules, splice in
`services.sapohub`, `nixos-rebuild switch`. After that,
deploy from the Settings page — it pulls your config repo from GitHub,
syncs UI preferences back into it (`sapohub-prefs.nix`), and rebuilds,
streaming output into the UI.

**Git/nix is always the source of truth for a manual deploy.** The
Settings button runs `sapohub-deploy --sync-prefs`, which is the only
thing that ever writes local UI preference changes back into
`sapohub-prefs.nix`. A bare `sudo sapohub-deploy` — over SSH, from cron,
anywhere outside the UI — skips that sync and rebuilds from exactly
what's committed, full stop; it will never let an uncommitted local
preference change quietly override your config. Pending preference
changes aren't lost either way — they still apply live at runtime
(`SapoCore.Prefs` reads a local overlay first) and stay queued for the
next `--sync-prefs` deploy.

**Commit the empty `sapohub-prefs.nix` stub from the example and import it
from day one** (the example does this already), so that once you DO sync
preferences from Settings, they round-trip into your git-tracked config
and survive a redeploy onto a new host.

Snapshots: "Save all data" produces one tar.gz (SQLite backup + every
module's storage + manifest). Restore by deploying with
`sapohub-deploy --snapshot <file>` — it is staged and applied at boot,
before migrations, keeping a pre-restore DB backup.

## Verification

* `mix test` in `core/` — the full suite (core + all enabled modules).
* `nix build .#default` / `.#cli` — the composed release and CLI.
* `nix build .#checks.x86_64-linux.vm` — NixOS VM test (needs KVM):
  service boots, API serves, sudo is exactly one command, CLI round-trips.

## Writing a module

Read `docs/module-authoring.md`. Short version: `mix sapo.gen.module
my_thing`, implement `SapoKit.Module` callbacks (routes, migrations,
scheduler hooks, dashboard buttons, statusline items, settings tab, AI
context), use `SapoKit.*` facades for everything shared, never call
another module.
