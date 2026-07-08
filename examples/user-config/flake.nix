# The ONE file a SapoHub user writes: pick modules, set options, deploy.
#
#   nixos-rebuild switch --flake .#hub
#
# External modules plug in exactly like in-repo ones: add their flake as an
# input and put `inputs.<x>.sapohubModule` in the modules list.
{
  description = "My SapoHub";

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
          # inputs.my-module.sapohubModule
        ];
        # Update after changing the module set (nix prints the expected hash):
        depsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        apiBase = "http://my-host.example:4000/api";
      };
    in
    {
      nixosConfigurations.hub = sapohub.inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          sapohub.nixosModules.default
          # Machine-owned, kept in sync by deploys — see sapohub-prefs.nix.
          # Committed as an empty stub so this import works from the very
          # first `nixos-rebuild switch`, before any deploy has run.
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
                flakePath = "/home/me/hub-config";
                flakeAttr = "hub";
              };
              agentNotes = ''
                Times are UTC; user is in US Central.
              '';
              # assistant.browser.enable = true;
            };
          }
        ];
      };
    };
}
