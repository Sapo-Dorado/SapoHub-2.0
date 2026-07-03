{
  description = "SapoHub 2.0 - Nix-composed personal utility hub (Phoenix LiveView)";

  inputs = {
    # Pinned to the same rev as SapoHub v1 so the local store is warm.
    nixpkgs.url = "github:NixOS/nixpkgs/4df1b885d76a54e1aa1a318f8d16fd6005b6401f";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      # M6 will add:
      #   lib.mkSapoHub       - compose enabled modules into a release (nix/compose.nix)
      #   nixosModules.default - services.sapohub (nix/nixos-module.nix)
      #   packages.default     - CI smoke build with the core module set

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          beamPkgs = pkgs.beam.packages.erlang_27;
        in
        {
          default = pkgs.mkShell {
            packages = [
              beamPkgs.elixir_1_18
              beamPkgs.erlang
              pkgs.nodejs_22
              pkgs.sqlite
              pkgs.tailwindcss
              pkgs.esbuild
              pkgs.inotify-tools
            ];

            shellHook = ''
              export MIX_HOME="$PWD/.mix"
              export HEX_HOME="$PWD/.hex"
              export PATH="$MIX_HOME/escripts:$PATH"
              export ERL_AFLAGS="-kernel shell_history enabled"
            '';
          };
        });
    };
}
