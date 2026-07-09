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

      # ── Fresh-machine (nixos-anywhere) host builder ─────────────────────────
      # One nixosSystem per physical/virtual machine you bootstrap. Convention:
      # the nixosConfigurations attribute name IS the hostname IS the prefix
      # for that host's generated hardware files — `hardware/<hostname>-
      # hardware-configuration.nix` / `hardware/<hostname>-disk-device.nix` —
      # so ANY config repo (this one's own `fresh-machine` example, or a
      # user's personal config repo) can bootstrap multiple distinct hosts
      # from the same flake without one overwriting another's hardware config.
      # scripts/bootstrap.sh writes those files (via nixos-anywhere's
      # --generate-hardware-config) and commits them into whichever repo
      # --flake-path points at — see that script for the full mechanism.
      #
      # hardwareDir MUST be a path from the CALLING flake (typically
      # `./hardware` in whatever repo defines nixosConfigurations.<hostname>),
      # not from this one — hardware config is per-repo, not shipped here.
      lib.mkFreshMachine =
        { hostname
        , hardwareDir
        , sshKey
        , modules
        , depsHash
        , npmDepsHash
        , system ? "x86_64-linux"
        , secretsFile ? "/etc/sapohub/secrets.env"
        , tailscaleAuthKeyFile ? "/etc/sapohub/tailscale-authkey"
        , deployFlakePath ? "/etc/sapohub-config"
          # Extra NixOS modules appended after everything below — e.g. a
          # ./sapohub-prefs.nix import, or per-host overrides. NOT to be
          # confused with `modules` above (the SapoHub *utility* modules
          # passed to mkSapoHub, e.g. sapohubModules.my_plate).
        , extraNixosModules ? [ ]
        }:
        let
          built = self.lib.mkSapoHub { inherit system modules depsHash npmDepsHash; };

          hwGenerated = hardwareDir + "/${hostname}-hardware-configuration.nix";
          hwExample = hardwareDir + "/example-hardware-configuration.nix";
          hardwareConfigPath = if builtins.pathExists hwGenerated then hwGenerated else hwExample;

          diskGenerated = hardwareDir + "/${hostname}-disk-device.nix";
          diskExample = hardwareDir + "/example-disk-device.nix";
          diskDeviceFile = if builtins.pathExists diskGenerated then diskGenerated else diskExample;
          inherit (import diskDeviceFile) sapohubDiskDevice;
        in
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            disko.nixosModules.disko
            self.nixosModules.default
            hardwareConfigPath
            {
              disko.devices.disk.main = {
                device = sapohubDiskDevice;
                type = "disk";
                content = {
                  type = "gpt";
                  partitions = {
                    boot = { size = "1M"; type = "EF02"; };
                    swap = { size = "2G"; content.type = "swap"; };
                    root = {
                      size = "100%";
                      content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; };
                    };
                  };
                };
              };
            }

            ({ pkgs, lib, ... }:
              let
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
                networking.firewall.allowedTCPPorts = [ 22 ];

                # ---- Application ----
                # Reachable at https://<tailscale-hostname> once joined (and,
                # one time, "HTTPS Certificates" is turned on for the tailnet
                # in the Tailscale admin console — see services.sapohub.
                # nginx.https) — no domain/public TLS needed on a
                # Tailscale-only box. Tailscale itself (the only network path
                # in; no public exposure) is services.sapohub.tailscale —
                # same option an existing-config user can opt into, just
                # defaulted on here. nginx is the sole path in either way:
                # the app's own port is loopback-only whenever nginx.enable
                # is true (the default).
                services.sapohub = {
                  enable = true;
                  package = built.package;
                  cliPackage = built.cli;
                  inherit secretsFile;
                  assistant.claudePackage = flakePkgs.claude-code;
                  tailscale = {
                    enable = true;
                    authKeyFile = tailscaleAuthKeyFile;
                  };
                  nginx.https = true;
                  deploy = {
                    flakePath = deployFlakePath;
                    flakeAttr = hostname;
                  };
                };

                nixpkgs.config.allowUnfree = true;
                environment.systemPackages = [ flakePkgs.claude-code pkgs.google-chrome ];

                networking.hostName = hostname;
                boot.loader.grub.enable = true;
                boot.loader.grub.efiSupport = false;

                system.stateVersion = "24.11";
              })
          ] ++ extraNixosModules;
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
      # scripts/bootstrap.sh <ip> --hostname fresh-machine targets this by
      # default. It's Tailscale-only by design — no public ACME/firewall
      # (nginx fronts the app on port 80 by default, services.sapohub.nginx),
      # matching how SapoHub is actually meant to be reached (see
      # README's "Fresh machine" section). CHANGE sshKey below for your own
      # deploy — or better, don't deploy against THIS repo's own example at
      # all: point --flake-path at a personal config repo that calls
      # `sapohub.lib.mkFreshMachine` itself instead (see examples/README.md
      # and hardware/README.md for the "existing config" alternative, or
      # start a personal repo from examples/user-config/).
      nixosConfigurations.fresh-machine = self.lib.mkFreshMachine {
        hostname = "fresh-machine";
        hardwareDir = ./hardware;
        sshKey = "ssh-ed25519 AAAA..."; # CHANGE ME — your SSH public key
        modules = [ self.sapohubModules.hello self.sapohubModules.my_plate ];
        depsHash = "sha256-2gMs2ZCx1FHah25Zm/vYlSt5TQEZyZ92jHd3u1o6iW4=";
        npmDepsHash = "sha256-iHOJ/cXZOsPeEnKaDBYbEj7ClLpJ5hbmrZwnLmTvrdU=";
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
