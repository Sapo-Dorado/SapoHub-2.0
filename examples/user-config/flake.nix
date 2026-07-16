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
# `modules`/`depsHash`/`npmDepsHash` are each defined ONCE below
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
      lib = sapohub.inputs.nixpkgs.lib;

      modules = [
        sapohub.sapohubModules.hello
        sapohub.sapohubModules.my_plate
        # inputs.my-module.sapohubModule
      ];
      # Update after changing the module set (nix prints the expected hash):
      depsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

      # Machine-owned, written by `sapohub-deploy --sync-prefs` into
      # .sapohub/sapohub-prefs.nix at THIS repo's own root — every config
      # repo that's an actual deploy.flakePath target needs this same line
      # (see nix/deploy-script.nix for what writes it). No stub file needs
      # to exist up front; pathExists just skips it until the first sync.
      prefsImport = lib.optional (builtins.pathExists ./.sapohub/sapohub-prefs.nix) ./.sapohub/sapohub-prefs.nix;

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
      ] ++ prefsImport ++ [
        {
          services.sapohub = {
            enable = true;
            package = hub.package;
            cliPackage = hub.cli;
            # hostPackages (yt-dlp, etc. from your modules) is picked up
            # automatically off hub.package's passthru — no line needed
            # here. Only set it explicitly if you want to add/replace a
            # binary without rebuilding package.
            host = "my-host.example";
            port = 4000;
            # secretsFile and deploy.flakePath already default to
            # /etc/sapohub/secrets.env and /etc/sapohub-config — only
            # override if yours actually live somewhere else.
            deploy.flakeAttr = "your-host"; # YOUR nixosConfigurations attr name, not "hub"
            # Optional: set this to this repo's own HTTPS URL and the box
            # seeds /etc/sapohub-config itself on first boot — no manual
            # `git clone` needed before your first `sapohub-deploy`/Deploy
            # button press. Leave unset if you're managing that checkout
            # some other way already.
            #
            # IMPORTANT if you're layering configs (e.g. this file itself
            # gets imported by a FURTHER outer flake, rather than being
            # your top-level config directly): deploy.repoUrl/flakePath
            # must always point at whichever flake is the true outermost
            # one — the one that actually defines
            # nixosConfigurations.<flakeAttr>. Never leave it to a default
            # inherited from an imported dependency; unlike flakeAttr
            # (which has no default and forces you to set it), repoUrl
            # DOES have one and can silently carry over from whatever you
            # import, pointing sapohub-deploy at the wrong repo entirely.
            # deploy.repoUrl = "https://github.com/you/your-config-repo";
            # assistant.browser.enable = true;
            #
            # If your setup layers a further flake on top of THIS one
            # (importing it as `sapohub.sapohubModule`-style dependency
            # rather than being the top-level config), that outer flake
            # also needs deploy.updateInputNames set to reach through
            # this one — e.g. `[ "my-config/sapohub" ]` if it names this
            # input "my-config" — so `deploy.autoUpdateInputs` (on by
            # default) actually bumps the right transitive pin instead of
            # a nonexistent top-level "sapohub" input. See
            # services.sapohub.deploy's option docs in SapoHub-2.0's
            # nix/nixos-module.nix for the full autoUpdateInputs/
            # updateInputNames explanation.
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
      # instead of importing the module above (e.g. to reorder relative to
      # other modules).
      inherit sapohubModulesForHost;
    };
}
