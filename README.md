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
examples/    user-config/flake.nix — the ONE file a user writes
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

Write one flake (see `examples/user-config/flake.nix`): pick modules,
set `services.sapohub` options, `nixos-rebuild switch`. After that,
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
