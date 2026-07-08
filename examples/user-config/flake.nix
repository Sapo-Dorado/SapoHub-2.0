# Add SapoHub to a NixOS box you already manage.
#
# This demonstrates PATH 2 of the two ways to run SapoHub:
#   1. Fresh machine, don't own a NixOS config yet — use
#      ./scripts/bootstrap.sh <ip> in the SapoHub repo instead, which
#      targets nixosConfigurations.fresh-machine (disko + generated
#      hardware config + nixos-anywhere). Nothing in THIS directory is
#      needed for that path.
#   2. Existing NixOS box, own config already — THIS file. It only shows
#      the bits you add: the flake input, `sapohub.nixosModules.default`,
#      and a `services.sapohub = { ... }` block. It deliberately does NOT
#      define `fileSystems`, `boot.loader`, or a hardware-configuration.nix
#      import — that's yours already, and pasting a fake one over it would
#      be actively wrong. Splice the pieces below into your OWN
#      `nixosConfigurations.<your-host>`'s `modules` list; don't build this
#      file's `nixosConfigurations.hub` output standalone (it will fail to
#      evaluate — no filesystems/bootloader — on purpose, so it can't be
#      mistaken for something deployable as-is).
#
# External modules plug in exactly like in-repo ones: add their flake as an
# input and put `inputs.<x>.sapohubModule` in the modules list below.
{
  description = "My SapoHub (existing-config example — see header comment)";

  inputs = {
    sapohub.url = "github:Sapo-Dorado/SapoHub-2.0";
    # my-module.url = "github:someone/sapohub-my-module";
  };

  outputs = { self, sapohub, ... }@inputs:
    let
      system = "x86_64-linux";

      hub = sapohub.lib.mkSapoHub {
        inherit system;
        modules = [
          sapohub.sapohubModules.hello
          sapohub.sapohubModules.my_plate
          # inputs.my-module.sapohubModule
        ];
        # Update after changing the module set (nix prints the expected hash):
        depsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        apiBase = "http://my-host.example:4000/api";
      };

      # ── Everything from here down is what you actually copy ──────────────
      # Into YOUR existing nixosConfigurations.<your-host>'s `modules` list,
      # alongside whatever you already have (fileSystems, boot.loader, your
      # existing hardware-configuration.nix import, other services, ...).
      # Nothing here assumes it owns the whole host.
      sapohubModulesForHost = [
        sapohub.nixosModules.default
        # Machine-owned, kept in sync by deploys — see sapohub-prefs.nix.
        # Committed as an empty stub so this import works from the very
        # first `nixos-rebuild switch`, before any deploy has run. Copy
        # sapohub-prefs.nix alongside your own flake.nix too.
        ./sapohub-prefs.nix
        {
          services.sapohub = {
            enable = true;
            package = hub.package;
            cliPackage = hub.cli;
            host = "my-host.example";
            port = 4000;
            secretsFile = "/etc/sapohub/secrets.env";
            deploy = {
              flakePath = "/home/me/hub-config"; # wherever YOUR config repo lives on the host
              flakeAttr = "your-host"; # YOUR nixosConfigurations attr name, not "hub"
            };
            agentNotes = ''
              Times are UTC; user is in US Central.
            '';
            # assistant.browser.enable = true;
          };
        }
      ];
    in
    {
      # Exposed only so this example evaluates for `nix flake check` /
      # inspection (e.g. `nix eval .#sapohubModulesForHost`) — it is
      # intentionally NOT a `nixosConfigurations` output, since this repo
      # doesn't own a real host (no fileSystems/bootloader/hardware config
      # to give it). Building `nix build .#nixosConfigurations.hub...`
      # against this file is not the point; splicing
      # `sapohubModulesForHost` into your own config is.
      inherit sapohubModulesForHost;
    };
}
