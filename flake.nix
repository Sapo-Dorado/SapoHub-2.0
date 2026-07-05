{
  description = "SapoHub 2.0 - Nix-composed personal utility hub (Phoenix LiveView)";

  inputs = {
    # Pinned to the same rev as SapoHub v1 so the local store is warm.
    nixpkgs.url = "github:NixOS/nixpkgs/4df1b885d76a54e1aa1a318f8d16fd6005b6401f";
    # Newer nixpkgs ONLY for tools missing from the pinned rev (tailwind v4).
    nixpkgs-tools.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-tools }:
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
          jsHooks = false;
        };
      };

      nixosModules.default = import ./nix/nixos-module.nix { inherit self; };

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

              # The expty precompiled NIF ships a spawn-helper binary linked
              # against the generic /lib64 dynamic linker, which does not
              # exist on NixOS. Patch any copies in _build (idempotent,
              # dev-only; M6's mixRelease does the same for releases).
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
