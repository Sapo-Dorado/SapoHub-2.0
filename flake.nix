{
  description = "SapoHub 2.0 - Nix-composed personal utility hub (Phoenix LiveView)";

  inputs = {
    # Pinned to the same rev as SapoHub v1 so the local store is warm.
    nixpkgs.url = "github:NixOS/nixpkgs/4df1b885d76a54e1aa1a318f8d16fd6005b6401f";
    # Newer nixpkgs ONLY for tools missing from the pinned rev (tailwind v4).
    nixpkgs-tools.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Disk partitioning for the fresh-machine nixos-anywhere path (below).
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Real `claude` CLI for the assistant module — unfree, so it's an
    # overlay applied only where actually needed (the fresh-machine example
    # target), not forced on every downstream flake that composes SapoHub.
    claude-code-nix.url = "github:sadjow/claude-code-nix";
  };

  outputs = { self, nixpkgs, nixpkgs-tools, disko, claude-code-nix }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      # ── Composition API ────────────────────────────────────────────────────
      # User configs call lib.mkSapoHub to build the release + CLI for their
      # module set, then import nixosModules.default and set services.sapohub.
      lib.mkSapoHub = { system, modules, depsHash, npmDepsHash, apiBase ? "http://localhost:4000/api" }:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          toolsPkgs = nixpkgs-tools.legacyPackages.${system};
          beamPkgs = pkgs.beam.packages.erlang_27;
          compose = import ./nix/compose.nix {
            inherit pkgs beamPkgs;
            lib = nixpkgs.lib;
            elixir = beamPkgs.elixir_1_18;
            tailwind = toolsPkgs.tailwindcss_4;
          };
          mkCli = import ./nix/cli.nix { inherit pkgs; lib = nixpkgs.lib; };
        in {
          package = compose {
            src = self;
            inherit modules depsHash npmDepsHash;
          };
          cli = mkCli { src = self; inherit modules apiBase; };
        };

      # In-repo module packaging attrsets (external modules export the same
      # shape as `sapohubModule` from their own flakes).
      sapohubModules = {
        hello = {
          name = "hello";
          app = "sapo_hello";
          src = ./modules/hello;
          elixirModule = "SapoHello.Module";
          config = { };
          cliFragment = true;
          jsHooks = false;
        };
        my_plate = {
          name = "my_plate";
          app = "my_plate";
          src = ./modules/my_plate;
          elixirModule = "MyPlate.Module";
          config = { };
          cliFragment = true;
          jsHooks = true;
        };
      };

      nixosModules.default = import ./nix/nixos-module.nix { inherit self; };

      # ── Fresh-machine bootstrap target (nixos-anywhere) ─────────────────────
      # scripts/bootstrap.sh <ip> targets this. It's Tailscale-only by design —
      # no public nginx/ACME/firewall, matching how SapoHub is actually meant
      # to be reached (see README's "Fresh machine" section). Works on
      # arbitrary hardware: the disk device (nix/disko-config.nix) and the
      # hardware-configuration.nix (imported below) are both generated
      # per-machine by the bootstrap script via nixos-anywhere's
      # --generate-hardware-config, not hardcoded here. CHANGE the sshKey /
      # tailscaleAuthKeyFile / secretsFile below for your own deploy — or
      # better, copy this whole block into your own flake and start from
      # there (see the "existing config" example under examples/ for how to
      # fold nixosModules.default into a config you already own instead).
      nixosConfigurations.fresh-machine =
        let
          system = "x86_64-linux";
          built = self.lib.mkSapoHub {
            inherit system;
            modules = [ self.sapohubModules.hello self.sapohubModules.my_plate ];
            depsHash = "sha256-2gMs2ZCx1FHah25Zm/vYlSt5TQEZyZ92jHd3u1o6iW4=";
            npmDepsHash = "sha256-iHOJ/cXZOsPeEnKaDBYbEj7ClLpJ5hbmrZwnLmTvrdU=";
          };
        in
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            disko.nixosModules.disko
            ./nix/disko-config.nix
            self.nixosModules.default
            (
              if builtins.pathExists ./hardware/generated-hardware-configuration.nix
              then ./hardware/generated-hardware-configuration.nix
              else ./hardware/example-hardware-configuration.nix
            )

            ({ pkgs, lib, ... }:
              let
                sshKey = "ssh-ed25519 AAAA..."; # CHANGE ME — your SSH public key
                # scripts/bootstrap.sh can seed an authkey file at this path
                # before first boot (see README) so the machine joins your
                # tailnet unattended; omit --auth-key-file to skip and run
                # `tailscale up` by hand after the first boot instead.
                tailscaleAuthKeyFile = "/etc/sapohub/tailscale-authkey";
                flakePkgs = import nixpkgs {
                  inherit (pkgs) system;
                  config.allowUnfree = true;
                  overlays = [ claude-code-nix.overlays.default ];
                };
              in
              {
                # ---- SSH access ----
                users.users.root.openssh.authorizedKeys.keys = [ sshKey ];
                services.openssh.enable = true;

                # ---- Tailscale (the only network path in; no public exposure) ----
                services.tailscale.enable = true;
                networking.firewall.trustedInterfaces = [ "tailscale0" ];
                networking.firewall.allowedTCPPorts = [ 22 ];
                systemd.services.tailscale-autoconnect = {
                  description = "Join the tailnet on first boot, if an authkey is present";
                  after = [ "network-pre.target" "tailscale.service" ];
                  wants = [ "network-pre.target" "tailscale.service" ];
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig.Type = "oneshot";
                  script = ''
                    ${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' >/dev/null && exit 0
                    if [ -f "${tailscaleAuthKeyFile}" ]; then
                      ${pkgs.tailscale}/bin/tailscale up --auth-key "file:${tailscaleAuthKeyFile}"
                    fi
                  '';
                };

                # ---- Application ----
                # Reachable at http://<tailscale-hostname>:4000 once joined —
                # no domain/TLS needed on a Tailscale-only box. Set `host` to
                # your actual tailnet hostname once you know it, so
                # PHX_HOST/URL generation match (cosmetic; doesn't block
                # first boot).
                services.sapohub = {
                  enable = true;
                  package = built.package;
                  cliPackage = built.cli;
                  host = "localhost";
                  secretsFile = "/etc/sapohub/secrets.env"; # CHANGE ME — seed before bootstrap, see README
                  assistant.claudePackage = flakePkgs.claude-code;
                  deploy = {
                    flakePath = "/etc/sapohub-config"; # CHANGE ME — where you'll check out your config repo
                    flakeAttr = "fresh-machine";
                  };
                };

                nixpkgs.config.allowUnfree = true;
                environment.systemPackages = [ flakePkgs.claude-code pkgs.google-chrome ];

                networking.hostName = "sapohub";
                boot.loader.grub.enable = true;
                boot.loader.grub.efiSupport = false;

                system.stateVersion = "24.11";
              })
          ];
        };

      # CI smoke build: core + the default module set.
      packages = forAllSystems (system:
        let
          built = self.lib.mkSapoHub {
            inherit system;
            modules = [ self.sapohubModules.hello self.sapohubModules.my_plate ];
            depsHash = "sha256-2gMs2ZCx1FHah25Zm/vYlSt5TQEZyZ92jHd3u1o6iW4=";
            npmDepsHash = "sha256-iHOJ/cXZOsPeEnKaDBYbEj7ClLpJ5hbmrZwnLmTvrdU=";
          };
        in {
          default = built.package;
          cli = built.cli;
        });

      # NixOS VM test (needs KVM; run via `nix build .#checks.x86_64-linux.vm`):
      # service boots + serves the API, exactly ONE sudo command, composed
      # CLI works against the live hub.
      checks.x86_64-linux =
        let
          system = "x86_64-linux";
          pkgs = nixpkgs.legacyPackages.${system};
          built = self.lib.mkSapoHub {
            inherit system;
            modules = [ self.sapohubModules.hello self.sapohubModules.my_plate ];
            depsHash = "sha256-2gMs2ZCx1FHah25Zm/vYlSt5TQEZyZ92jHd3u1o6iW4=";
            npmDepsHash = "sha256-iHOJ/cXZOsPeEnKaDBYbEj7ClLpJ5hbmrZwnLmTvrdU=";
          };
        in
        {
          vm = pkgs.testers.runNixOSTest {
            name = "sapohub";

            nodes.machine = { pkgs, ... }: {
              imports = [ self.nixosModules.default ];

              virtualisation.memorySize = 2048;
              virtualisation.diskSize = 4096;

              environment.etc."sapohub-secrets.env".text = ''
                SECRET_KEY_BASE=vm-test-secret-key-base-vm-test-secret-key-base-vm-test-secret-1
              '';

              services.sapohub = {
                enable = true;
                package = built.package;
                cliPackage = built.cli;
                host = "localhost";
                port = 4000;
                secretsFile = "/etc/sapohub-secrets.env";
                # Real claude-code is unfree; the VM only needs the PATH
                # wiring, not a working assistant.
                assistant.claudePackage =
                  pkgs.writeShellScriptBin "claude" "echo claude-stub";
                deploy = {
                  flakePath = "/tmp/hub-config";
                  flakeAttr = "hub";
                };
              };
            };

            testScript = ''
              machine.start()
              machine.wait_for_unit("sapohub.service")
              machine.wait_for_open_port(4000)

              # API up, context served, modules present.
              ctx = machine.succeed("curl -sf http://localhost:4000/api/claude-context")
              assert "SapoHub" in ctx and "my_plate" in ctx

              # Restricted sudo: EXACTLY one NOPASSWD command.
              rules = machine.succeed("sudo -l -U sapohub")
              assert "sapohub-deploy" in rules
              assert rules.count("NOPASSWD") == 1

              # Composed CLI round-trips against the live hub.
              machine.succeed("sapo tasks create vm-task --priority high")
              out = machine.succeed("sapo tasks list")
              assert "vm-task" in out

              # Snapshot save via CLI, file lands in the state dir.
              machine.succeed("sapo snapshot save")
              machine.succeed("ls /var/lib/sapohub/snapshots/ | grep -q sapohub-")
            '';
          };
        };

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          toolsPkgs = nixpkgs-tools.legacyPackages.${system};
          beamPkgs = pkgs.beam.packages.erlang_27;

          # expty ships a precompiled NIF; elixir_make/cc_precompiler will
          # otherwise fetch it ad hoc over the network on first `mix deps.get`
          # — same URL as the release build (compose.nix) uses, but WITHOUT
          # the hash pin nix normally gives you, so a flaky/interrupted
          # download can leave a corrupt spawn-helper in _build that still
          # LOOKS like a valid ELF (right header, right size ballpark) but
          # fails `posix_spawn` with `Exec format error` — patchelf'ing its
          # interpreter/rpath doesn't help, because the file itself is bad,
          # not just mis-linked. Pre-fetch the exact release-verified
          # tarball here too, so the dev shell can never end up with a
          # different (and possibly broken) copy than what ships to prod.
          exptyNif = pkgs.fetchurl {
            url = "https://github.com/cocoa-xu/expty/releases/download/v0.2.1/expty-nif-2.16-x86_64-linux-gnu-0.2.1.tar.gz";
            hash = "sha256-HDLUODEpP6p0X/u0/HBux33V1pJb54xRF610F62HIcg=";
          };
        in
        {
          default = pkgs.mkShell {
            packages = [
              beamPkgs.elixir_1_18
              beamPkgs.erlang
              pkgs.nodejs_22
              pkgs.sqlite
              toolsPkgs.tailwindcss_4
              pkgs.esbuild
              pkgs.inotify-tools
              pkgs.patchelf
              pkgs.jq
              pkgs.curl
            ];

            shellHook = ''
              export MIX_HOME="$PWD/.mix"
              export HEX_HOME="$PWD/.hex"
              export PATH="$MIX_HOME/escripts:$PATH"
              export ERL_AFLAGS="-kernel shell_history enabled"
              # Dev-assembled sapo CLI (mix sapo.gen.cli) lives in _build.
              export PATH="$PWD/core/_build/dev:$PATH"
              # Use the nix-built tailwind v4 instead of the generic-linux
              # binary the `mix tailwind` installer downloads (segfaults after
              # patchelf; Bun-compiled binaries don't tolerate it).
              export TAILWIND_PATH="${toolsPkgs.tailwindcss_4}/bin/tailwindcss"
              export ESBUILD_PATH="${pkgs.esbuild}/bin/esbuild"

              # Point elixir_make/cc_precompiler at the same hash-verified
              # expty NIF tarball the release build uses, so `mix deps.get`
              # / `mix compile` here can't silently pick up a different (or
              # corrupt) artifact. Safe to re-run every shell entry.
              export ELIXIR_MAKE_CACHE_DIR="$PWD/.elixir_make_cache"
              mkdir -p "$ELIXIR_MAKE_CACHE_DIR"
              cp -f ${exptyNif} "$ELIXIR_MAKE_CACHE_DIR/expty-nif-2.16-x86_64-linux-gnu-0.2.1.tar.gz"

              # The expty precompiled NIF ships a spawn-helper binary linked
              # against the generic /lib64 dynamic linker, which does not
              # exist on NixOS. Patch any copies in _build (idempotent,
              # dev-only; M6's mixRelease does the same for releases). If
              # you still see `Exec format error` after this, the copy in
              # _build predates the ELIXIR_MAKE_CACHE_DIR pin above — force
              # a clean recompile: `mix deps.compile expty --force`.
              for helper in core/_build/*/lib/expty/priv/spawn-helper; do
                if [ -f "$helper" ]; then
                  patchelf \
                    --set-interpreter "$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)" \
                    --set-rpath "${pkgs.stdenv.cc.cc.lib}/lib" \
                    "$helper" 2>/dev/null || true
                fi
              done

              # Same treatment for the tailwind v4 standalone binary that the
              # `mix tailwind` installer downloads (generic-linux linked).
              for tw in core/_build/tailwind-linux-*; do
                if [ -f "$tw" ]; then
                  patchelf \
                    --set-interpreter "$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)" \
                    --set-rpath "${pkgs.stdenv.cc.cc.lib}/lib" \
                    "$tw" 2>/dev/null || true
                fi
              done
            '';
          };
        });
    };
}
