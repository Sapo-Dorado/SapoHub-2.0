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

Entry point: `./scripts/bootstrap.sh <ip> --hostname <name> [options]`.
`--hostname` is required — it's both the `nixosConfigurations` attribute
built and the prefix for that machine's generated hardware files
(`hardware/<hostname>-hardware-configuration.nix`,
`hardware/<hostname>-disk-device.nix`), which is what lets one config
repo manage several distinct hosts over time (`lib.mkFreshMachine` in
SapoHub-2.0's flake.nix, `hosts` attrset in a personal config repo like
`sapohub-config`) without one host's hardware config clobbering
another's. Reuse the same `--hostname` for every future
bootstrap/rebuild of a given machine; pick a new one for a different
machine.

Pass `--flake-path <path>` to target a personal config repo instead of
SapoHub-2.0's own bundled `fresh-machine` example (default: this
script's own repo) — that's the normal case once someone has their own
config repo (see `examples/README.md`).

Read the script itself (`scripts/bootstrap.sh`) before running it — it's
short, heavily commented, and the comments explain exactly what each
step does and why (hardware-config generation, disk device override,
secrets seeding via `--extra-files`, committing+pushing the generated
hardware files into `--flake-path` so future redeploys have the real
config rather than a placeholder, the post-install git clone that seeds
`/etc/sapohub-config` on the target).

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
   rather run `tailscale up` by hand after bootstrap. This is the one
   genuinely one-time, per-machine manual step even on the fully
   scripted fresh-machine path — `lib.mkFreshMachine` sets
   `services.sapohub.tailscale.enable = true;` (a real module option, see
   Path 2 below for the non-fresh-machine case), but joining an
   ACCOUNT's tailnet needs either an auth key (generate one at
   https://login.tailscale.com/admin/settings/keys, save it to a file,
   pass `--tailscale-auth-key-file <path>` — the script seeds it to
   `/etc/sapohub/tailscale-authkey` and the autoconnect unit picks it up
   on first boot, no login prompt) or an interactive `ssh root@<ip>
   tailscale up` afterward (prints a URL to open and approve in a
   browser). Either way it's once per machine — Tailscale state persists
   in `/var/lib/tailscale` across every future `nixos-rebuild`/redeploy,
   it doesn't need repeating.

   On the manual `tailscale up` path specifically: at first boot, before
   Tailscale is joined, `sapohub-tailscale-cert` (fetches the box's
   Tailscale HTTPS cert for nginx) has nothing to fetch a cert from and
   fails; nginx's `ExecStartPre` then fails too and systemd gives up
   after its retry budget, leaving both services sitting `failed`
   (nginx) / `inactive (dead)` (start-limit-hit) — they do NOT
   self-heal once Tailscale later joins. After the user approves the
   `tailscale up` login, restart both by hand: `systemctl restart
   sapohub-tailscale-cert; systemctl reset-failed nginx; systemctl
   restart nginx`. This is expected on this path, not a bug — the
   auth-key path avoids it entirely because Tailscale is already up
   before the cert/nginx units ever get their first chance to start.

The script asks for IP re-confirmation immediately before the
destructive nixos-anywhere run — don't route around that by scripting
the confirmation input; let the user actually see and confirm it.

**Customizing a fresh-machine target** (module selection,
`assistant.browser.enable`, etc.) means editing the
`sapohub.lib.mkFreshMachine { ... }` call for that host — either
SapoHub-2.0's own `nixosConfigurations.fresh-machine` block, or (the
normal case) the `hosts`/`mkHost` setup in a personal config repo like
`sapohub-config`, which has one call per hostname and a place to pass
`extraNixosModules` for anything `mkFreshMachine` doesn't take directly —
including the conditional `.sapohub/sapohub-prefs.nix` import (see
`sapohub-config`'s own `flake.nix` for the `prefsImport` pattern). Read
`lib.mkFreshMachine`'s
definition in SapoHub-2.0's root `flake.nix` for the current parameter
list rather than assuming it hasn't changed.

If nixos-anywhere fails partway through (common: SSH key issues, wrong
disk device, target not actually in an installer environment), it's
usually safe to just fix the issue and re-run `bootstrap.sh` — disko
repartitions from scratch each time, and the hardware-config/disk-device
override files get regenerated fresh on every run.

## Path 2: existing NixOS config

Tailscale IS a real `services.sapohub` option
(`services.sapohub.tailscale.{enable,authKeyFile}`, in
`nix/nixos-module.nix`) — `lib.mkFreshMachine` just sets it for you.
It defaults to **disabled** on an existing-config machine, which keeps
whatever networking it already has; don't turn it on for the user
unless they ask for it separately. If they do want it:
`services.sapohub.tailscale.enable = true;` (+ optionally
`authKeyFile = "/path/to/authkey";` for unattended join — see the
Tailscale auth-key precondition above, same mechanism). Everything else
(firewall `trustedInterfaces`, the `tailscale-autoconnect` unit) is
handled by the option; nothing else to wire up by hand. General
firewall/SSH-port config beyond that is still the user's own, untouched
by this module.

Two ways to do this, in order of preference:

**2a. The user already has (or is willing to make) their own personal
config repo with a `nixosModules.default` output** — e.g. one built the
way `sapohub-config` (see `examples/README.md` for how such a repo is
structured) exposes its own module. In that case adding SapoHub to an
existing NixOS config is just:
1. Add their config repo as a flake input in their existing config.
2. Append `<their-config-repo>.nixosModules.default` to the target
   `nixosConfigurations.<host>`'s `modules` list.
3. Set `services.sapohub.deploy.flakeAttr = "<host>";` — this is the one
   thing that can never have a sensible default (every config names its
   own host attribute), so it must always be set explicitly wherever the
   module gets imported. Everything else the module needs
   (`secretsFile`, `deploy.flakePath`) already defaults sensibly from
   SapoHub-2.0's own `nix/nixos-module.nix` — nothing to restate.
4. They run `nixos-rebuild switch --flake .#<host>` themselves.

This is the pattern to steer toward if the user is setting up a config
repo from scratch anyway — it means their personal config repo can be
imported into any number of existing machines' configs with a single
line, no `services.sapohub = { ... }` block required at all.

**2b. Manual splice, no separate config repo** — read
`examples/user-config/flake.nix` in full; its header comment and
`sapohubModulesForHost` list are the actual content to work from. Help
the user add `sapohub.nixosModules.default` plus a
`services.sapohub = { ... }` block directly into THEIR existing
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
4. Append `sapohub.nixosModules.default`, a conditional import of
   `.sapohub/sapohub-prefs.nix` (copy the `prefsImport` pattern from
   `examples/user-config/flake.nix` — `lib.optional (builtins.pathExists
   ./.sapohub/sapohub-prefs.nix) ./.sapohub/sapohub-prefs.nix`), and a
   `services.sapohub = {...}` block into their EXISTING
   `nixosConfigurations.<host>`'s `modules` list — don't create a new
   nixosConfigurations output. Only set values the user actually needs to
   override; `secretsFile` and `deploy.flakePath` already default sensibly
   and don't need restating. `deploy.flakeAttr` still must be set
   explicitly (see above). The prefs import can't be skipped or inherited
   from `sapohub.nixosModules.default` automatically — Nix's module system
   can't auto-detect that file (imports must resolve before any config
   value exists), so every top-level config repo needs this one line
   itself. No stub file needs to exist up front; `pathExists` just skips
   it until the first sync.
5. They run `nixos-rebuild switch --flake .#<their-attr>` themselves
   (or however they normally deploy their own config) — this skill
   doesn't run destructive commands against a machine you don't know
   the topology of.

Whichever sub-path is used, never invent option DEFAULTS inside a
downstream config repo or a one-off splice — if a value seems like it
should have a universally sensible default, that belongs as a real
`default = ...` on the option itself in `nix/nixos-module.nix` (or
whatever module owns it), not baked into every config that imports it.
A config repo's own module should only ever *set* values that are
genuinely specific to it (module selection, unfree-overlay wiring for
`assistant.claudePackage`, etc.).

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
  `.sapohub/sapohub-prefs.nix` by the Settings page's Deploy button
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
- **Tailscale** (`tailscale.enable`, `tailscale.authKeyFile`): off by
  default; turns on `services.tailscale`, `trustedInterfaces`, and a
  first-boot `tailscale-autoconnect` unit. `lib.mkFreshMachine` sets
  this for you; on an existing config it's opt-in (see Path 2 above).
- **nginx** (`nginx.enable`): **on by default** — nginx listens on port
  80 and proxies `/` to the app's own port on 127.0.0.1
  (`proxyWebsockets = true`, needed for LiveView). The app still binds
  its port directly too; nginx just adds a no-port-in-the-URL path
  (`http://<host>` instead of `http://<host>:4000`). Set
  `nginx.enable = false;` to skip it. This is also the prerequisite for
  an upcoming dev-session proxy slots feature (mirroring sapo-hub v1's
  `SapoHub.DevSessions`/`devSlots*` pattern — fixed nginx-fronted
  external ports mapped to internal ports a dev server binds to, so
  `sapo dev create`-style tunnels work against a SapoHub 2.0 box too) —
  not implemented yet, but will live in this same `services.nginx`
  config once it lands.
- **Assistant** (`assistant.claudePackage`, `assistant.workDir`,
  `assistant.browser.enable`): `claudePackage` needs the unfree
  `claude-code-nix` overlay applied to the `pkgs` used for that value —
  see how `nixosConfigurations.fresh-machine` in the root `flake.nix`
  does it (`import nixpkgs { config.allowUnfree = true; overlays = [
  claude-code-nix.overlays.default ]; }`) if the user's own config
  doesn't already have unfree packages allowed. `browser.enable` turns on
  a persistent Xvfb + Chrome pair for assistant sessions/skills that need
  a real browser (heavier; only enable if actually needed).

## Pairing Claude in Chrome with the assistant browser

`assistant.browser.enable` gives an agent session a persistent Chrome
(`chrome-sapohub` service, Xvfb on display `:99`, profile under
`${stateDir}/.config/google-chrome`) — but that only provisions the
browser. The `mcp__claude-in-chrome__*` tools still need the "Claude for
Chrome" extension installed and signed in inside that specific profile
before `list_connected_browsers` will ever show it, and that's an
interactive, one-time step no nix option automates (neither does
SapoHub-1, which used the exact same Xvfb+Chrome recipe and needed the
same manual pairing). This whole section only applies when
`services.sapohub.assistant.browser.enable = true;` for the install in
question — check the actual config for that host before bringing any
of this up (grep its `services.sapohub` block, or on a running box
`pgrep -af "Xvfb :99"`/`pgrep -af chrome`, owned by the `sapohub` user,
as a live proxy for the same thing). If it's off, either skip this
section entirely or, if the user wants browser access, set the option
and redeploy first — don't start a VNC session against a Chrome that
was never provisioned. Once confirmed on, do the pairing via a
throwaway VNC session onto display `:99`, approved by the human:

1. Fetch a VNC server on demand (nothing this heavy belongs in the
   system closure permanently): `nix-shell -p x11vnc --run "x11vnc ..."`.
2. Generate a random password rather than a fixed/predictable one and
   store it via x11vnc's own hashed format, not plaintext on the
   command line:
   ```
   mkdir -p /var/lib/sapohub/.vnc
   PASS=$(head -c 12 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
   nix-shell -p x11vnc --run "x11vnc -storepasswd '$PASS' /var/lib/sapohub/.vnc/passwd"
   chmod 600 /var/lib/sapohub/.vnc/passwd
   ```
   Show `$PASS` to the user once; it doesn't need to be remembered
   after this session.
3. Start it attached to `:99` specifically — never `:0` (the human's
   own desktop session, a completely different display/socket, e.g.
   `/tmp/.X11-unix/X0` vs `X99` — check `ls /tmp/.X11-unix/` and
   `loginctl list-sessions` if there's ever doubt which is which):
   ```
   nohup nix-shell -p x11vnc --run \
     "x11vnc -display :99 -rfbauth /var/lib/sapohub/.vnc/passwd -forever -shared -rfbport 5999 <bind-flag>" \
     > /var/lib/sapohub/.vnc/x11vnc.log 2>&1 &
   disown
   ```
   `<bind-flag>` depends on how the user will reach it — ask, don't
   assume:
   - Has an SSH client available (laptop/desktop): `-localhost`, then
     they run `ssh -L 5999:localhost:5999 <their-user>@<tailscale-ip>`
     and point a VNC client at `localhost:5999`. Safer default — the
     port never listens on any real interface.
   - Phone-only / no SSH client: `-listen <tailscale-ip>` (from
     `tailscale ip`) so the VNC client can connect directly to
     `<tailscale-ip>:5999`, no tunnel needed. Confirm this tradeoff
     with the user first — it's still password-protected, but now
     reachable from anywhere on their tailnet rather than only via an
     authenticated SSH session. **Never bind `0.0.0.0`/all-interfaces**
     — this box may not have `nginx.enable`'s loopback restriction
     protecting arbitrary ports.
   Whichever SSH user they tunnel through is irrelevant to *what* gets
   shown — that's determined entirely by `-display :99`, not by which
   Linux account authenticated the tunnel. (The `sapohub` service user
   itself typically has shell `nologin` and can't be SSH'd into
   directly — that's expected, not a problem to solve.)
4. Tell the user to connect, install "Claude for Chrome" from the
   Chrome Web Store inside that VNC session, sign in, and confirm any
   pairing prompt. No separate approval step was needed beyond that in
   practice — the extension just shows up in `list_connected_browsers`
   once signed in.
5. Back in the agent session: `list_connected_browsers` →
   `select_browser` with the returned `deviceId`. From then on the
   normal `mcp__claude-in-chrome__*` tools (navigate, computer, find,
   read_console_messages, ...) drive this exact browser.
6. Tear down x11vnc when done pairing (`pkill -f "x11vnc -display :99"`)
   — it's a throwaway setup aid, not something that needs to stay
   running. The paired extension and Chrome profile persist across
   `chrome-sapohub` restarts either way.

## Redeploying an already-running box

`sapohub-deploy` is installed on the target (via `environment.systemPackages`
in the module) and is the one thing the restricted sudoers rule allows.
SSH in and run it directly, or use the Settings page's Deploy button (adds
`--sync-prefs`). `nix/deploy-script.nix` is the actual implementation if
you need to understand exactly what it does — it's short and heavily
commented; read it rather than guessing at its behavior.

`sapohub-deploy --snapshot <file>` stages a snapshot for restore on the
service's next start (`Release.maybe_restore` runs in `ExecStartPre`,
as the `sapohub` service user — not root). The script chowns the staged
file to `sapohub:sapohub` before handing off, precisely because that
restore step can't read a root-owned file; if this regresses, the
symptom is the service crash-looping right after a `--snapshot` deploy
with `Permission denied` in `journalctl -u sapohub`, not anything
visible in the deploy script's own output (it reports success before
the file is ever read).

## What NOT to do

- Don't invent a disk layout, hardware config, or bootloader setting for
  an existing-config user — that's real, already-working config on their
  machine; changing it wrong can leave a box unbootable.
- Don't run `scripts/bootstrap.sh` or any nixos-anywhere invocation
  without the user explicitly confirming the target IP and that
  destroying the target's current disk contents is intended.
- Don't hand-write `.sapohub/sapohub-prefs.nix` content for a user — it's
  machine-owned and meant to be synced from the running app's Settings
  page, not authored directly.
