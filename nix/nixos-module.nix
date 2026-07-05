# services.sapohub — the NixOS module.
#
# The composed release (compose.nix) and CLI (cli.nix) are passed in as
# packages; the user's config flake builds them via lib.mkSapoHub and sets
# the options below. NO root for the app except the ONE restricted sudo
# command: sapohub-deploy.
{ self }:
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.sapohub;

  deployScript = import ./deploy-script.nix { inherit pkgs lib; } {
    flakePath = cfg.deploy.flakePath;
    flakeAttr = cfg.deploy.flakeAttr;
    stateDir = cfg.stateDir;
  };

  # ExPTY sets SIGCHLD=SIG_IGN in the forked child before exec'ing claude,
  # which breaks Node's child-process management (waitpid -> ECHILD). This
  # wrapper resets SIGCHLD to SIG_DFL first. (Proven fix from v1.)
  claudeWrapper = pkgs.stdenv.mkDerivation {
    name = "claude-sigchld-wrapper";
    src = pkgs.writeText "claude-wrapper.c" ''
      #include <signal.h>
      #include <unistd.h>
      #include <stdio.h>
      int main(int argc, char *argv[]) {
        signal(SIGCHLD, SIG_DFL);
        execv("${cfg.assistant.claudePackage}/bin/claude", argv);
        perror("execv: failed to launch claude");
        return 1;
      }
    '';
    dontUnpack = true;
    buildPhase = ''$CC -O2 -o claude $src'';
    installPhase = ''
      mkdir -p $out/bin
      cp claude $out/bin/claude
    '';
  };

  baseUrl = "${cfg.scheme}://${cfg.host}:${toString cfg.port}";

in
{
  options.services.sapohub = {
    enable = mkEnableOption "SapoHub 2.0";

    package = mkOption {
      type = types.package;
      description = "The composed SapoHub release (lib.mkSapoHub).";
    };

    cliPackage = mkOption {
      type = types.package;
      description = "The composed sapo CLI (lib.mkSapoHub).";
    };

    port = mkOption { type = types.port; default = 4000; };
    host = mkOption { type = types.str; default = "localhost"; };
    scheme = mkOption { type = types.enum [ "http" "https" ]; default = "http"; };

    secretsFile = mkOption {
      type = types.path;
      description = ''
        Root-owned env file with SECRET_KEY_BASE and any module secrets
        (validated at boot; module secrets degrade gracefully).
      '';
    };

    stateDir = mkOption { type = types.str; default = "/var/lib/sapohub"; };

    storageRoot = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Module file storage root (default: <stateDir>/storage).";
    };

    agentNotes = mkOption {
      type = types.lines;
      default = "";
      description = "Extra notes for AI agents, one per line (AI context).";
    };

    assistant = {
      workDir = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Working directory for assistant sessions (default: stateDir).";
      };

      claudePackage = mkOption {
        type = types.package;
        default = pkgs.claude-code;
        defaultText = literalExpression "pkgs.claude-code";
      };

      browser.enable = mkEnableOption ''
        a real Chrome with a graphical session on a virtual display
        (Xvfb :99, persistent profile) for assistant sessions and skills
      '';
    };

    deploy = {
      flakePath = mkOption {
        type = types.str;
        description = "Path of the user-config flake checkout (a git repo).";
      };
      flakeAttr = mkOption {
        type = types.str;
        description = "nixosConfigurations attribute to rebuild.";
      };
    };
  };

  config = mkIf cfg.enable (
    let
      storageRoot = if cfg.storageRoot != null then cfg.storageRoot else "${cfg.stateDir}/storage";
      workDir = if cfg.assistant.workDir != null then cfg.assistant.workDir else cfg.stateDir;
      bin = "${cfg.package}/bin/sapo_core";
    in
    {
      users.users.sapohub = {
        isSystemUser = true;
        group = "sapohub";
        extraGroups = [ "systemd-journal" ];
        home = cfg.stateDir;
        createHome = true;
        # Lingering lets the browser run as a systemd USER service, so the
        # app can restart it via `systemctl --user` without any root.
        linger = cfg.assistant.browser.enable;
      };
      users.groups.sapohub = { };

      # THE one root command (replaces v1's NOPASSWD:ALL).
      security.sudo.extraRules = [{
        users = [ "sapohub" ];
        commands = [{
          command = "/run/current-system/sw/bin/sapohub-deploy";
          options = [ "NOPASSWD" ];
        }];
      }];

      environment.systemPackages = [ cfg.cliPackage deployScript ];

      systemd.services.sapohub = {
        description = "SapoHub 2.0";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        environment = {
          PHX_SERVER = "true";
          PHX_HOST = cfg.host;
          PORT = toString cfg.port;
          DATABASE_PATH = "${cfg.stateDir}/db/sapohub.db";
          STORAGE_ROOT = storageRoot;
          SNAPSHOTS_DIR = "${cfg.stateDir}/snapshots";
          RESTORE_PENDING = "${cfg.stateDir}/db/restore/pending.tar.gz";
          ASSISTANT_WORKDIR = workDir;
          ASSISTANT_CHROME = if cfg.assistant.browser.enable then "true" else "false";
          AGENT_NOTES = cfg.agentNotes;
          SAPO_CLI_PATH = "${cfg.cliPackage}/bin/sapo";
          SAPO_API_BASE = "${baseUrl}/api";
          RELEASE_TMP = "${cfg.stateDir}/tmp";
          LANG = "en_US.UTF-8";
          # claude (SIGCHLD-fixed) first on PATH for assistant sessions.
          PATH = lib.mkForce
            "${lib.makeBinPath [
              claudeWrapper
              cfg.cliPackage
              pkgs.bash pkgs.coreutils pkgs.git pkgs.curl pkgs.jq
              pkgs.gnutar pkgs.gzip pkgs.openssh pkgs.sudo pkgs.systemd
            ]}:/run/current-system/sw/bin";
        };

        serviceConfig = {
          User = "sapohub";
          Group = "sapohub";
          WorkingDirectory = cfg.stateDir;
          EnvironmentFile = cfg.secretsFile;
          ExecStartPre = [
            "${pkgs.coreutils}/bin/mkdir -p ${cfg.stateDir}/db/restore ${cfg.stateDir}/snapshots ${cfg.stateDir}/tmp ${storageRoot}"
            # Restore a staged snapshot (if any), THEN migrate forward.
            "${bin} eval SapoCore.Release.maybe_restore()"
            "${bin} eval SapoCore.Release.migrate()"
          ];
          ExecStart = "${bin} start";
          Restart = "on-failure";
          RestartSec = 5;
        };
      };

      # ── Optional: real Chrome on a virtual display ────────────────────────
      systemd.services.xvfb-sapohub = mkIf cfg.assistant.browser.enable {
        description = "Virtual display for the SapoHub browser";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "sapohub";
          ExecStart = "${pkgs.xorg.xvfb}/bin/Xvfb :99 -screen 0 1920x1080x24";
          Restart = "always";
        };
      };

      systemd.user.services.chrome-sapohub = mkIf cfg.assistant.browser.enable {
        description = "SapoHub browser (persistent profile, display :99)";
        wantedBy = [ "default.target" ];
        environment.DISPLAY = ":99";
        serviceConfig = {
          ExecStartPre = "-${pkgs.coreutils}/bin/rm -f %h/.config/google-chrome/SingletonLock %h/.config/google-chrome/SingletonCookie %h/.config/google-chrome/SingletonSocket";
          ExecStart = "${pkgs.google-chrome}/bin/google-chrome-stable --user-data-dir=%h/.config/google-chrome --no-first-run --no-default-browser-check --disable-gpu --disable-software-rasterizer ${baseUrl}";
          Restart = "always";
        };
      };
    }
  );
}
