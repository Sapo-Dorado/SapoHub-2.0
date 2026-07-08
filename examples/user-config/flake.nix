# Add SapoHub to a NixOS box you already manage.
#
# This demonstrates PATH 2 of the two ways to run SapoHub:
#   1. Fresh machine, don't own a NixOS config yet — use
#      ./scripts/bootstrap.sh <ip> in the SapoHub repo instead, which
#      targets nixosConfigurations.fresh-machine (disko + generated
#      hardware config + nixos-anywhere). Nothing in THIS directory is
#      needed for that path.
#   2. Existing NixOS box, own config already — THIS file. It exposes a
#      `nixosModules.default` you import into your OWN
#      `nixosConfigurations.<your-host>`'s `modules` list — nothing else
#      required beyond that one import + setting `deploy.flakeAttr` (the
#      one value that can never have a sensible default, since it's
#      whatever you call your own host). It deliberately does NOT define
#      `fileSystems`, `boot.loader`, or a hardware-configuration.nix
#      import — that's yours already, and pasting a fake one over it
#      would be actively wrong.
#
# `modules`/`depsHash`/`npmDepsHash`/`prefs` are each defined ONCE below
# and referenced everywhere they're needed — the template to copy for
# your own config repo. See https://github.com/Sapo-Dorado/SapoHub-Config
# for a real, deployed instance built the same way (it also has its own
# nixosConfigurations.<host> for the fresh-machine path).
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

      modules = [
        sapohub.sapohubModules.hello
        sapohub.sapohubModules.my_plate
        # inputs.my-module.sapohubModule
      ];
      # Update after changing the module set (nix prints the expected hash):
      depsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

      # UI preferences you want hand-fixed rather than left to whatever's
      # synced from the Settings page (see sapohub-prefs.nix). Empty by
      # default — add entries like "dashboard_button.my_plate" = "preview";
      # here, not inline below, so there's exactly one place to edit.
      prefs = { };

      hub = sapohub.lib.mkSapoHub {
        inherit system modules depsHash npmDepsHash;
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
            # secretsFile and deploy.flakePath already default to
            # /etc/sapohub/secrets.env and /etc/sapohub-config — only
            # override if yours actually live somewhere else.
            deploy.flakeAttr = "your-host"; # YOUR nixosConfigurations attr name, not "hub"
            agentNotes = ''
              Times are UTC; user is in US Central.
            '';
            # assistant.browser.enable = true;
            inherit prefs; # plain assignment — wins over sapohub-prefs.nix's mkDefault-wrapped values
          };
        }
      ];
    in
    {
      # The actual importable module — `imports = [
      # my-config.nixosModules.default ];` plus `services.sapohub.deploy.
      # flakeAttr = "<your-host>";` in your own config is all that's
      # needed once you've forked/copied this file into your own repo.
      nixosModules.default = { ... }: {
        imports = sapohubModulesForHost;
      };

      # Exposed too, for anyone who'd rather splice the pieces by hand
      # instead of importing the module above (e.g. to omit
      # sapohub-prefs.nix, or reorder relative to other modules).
      inherit sapohubModulesForHost;
    };
}
