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
      default = "/etc/sapohub/secrets.env";
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

    prefs = mkOption {
      type = types.attrsOf (types.either types.str types.bool);
      default = { };
      example = {
        "dashboard_button.my_plate" = "preview";
        "dashboard_order" = "my_plate,sapo_hello,assistant";
        "statusline.core.snapshot" = false;
      };
      description = ''
        UI preferences (dashboard button variants, dashboard tile order,
        statusline toggles). Usually you don't write these by hand:
        Settings-page edits apply instantly via a local overlay, and a
        deploy run with `--sync-prefs` (the Settings "Deploy" button; see
        nix/deploy-script.nix) renders them into sapohub-prefs.nix in your
        config repo (lib.mkDefault, so anything set here directly wins).
        A bare manual `sapohub-deploy` never does this sync — git/nix
        stays authoritative for it.
      '';
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
        default = "/etc/sapohub-config";
        description = "Path of the user-config flake checkout (a git repo).";
      };
      flakeAttr = mkOption {
        type = types.str;
        description = ''
          nixosConfigurations attribute to rebuild. No universal default is
          possible — every config repo names its own hosts (the fresh-machine
          path uses the hostname; a spliced-into-existing-config setup uses
          whatever that config already calls itself). Always set explicitly.
        '';
      };
    };

    tailscale = {
      enable = mkEnableOption ''
        Tailscale on this box, plus a first-boot autoconnect unit. Off by
        default — an existing-config machine keeps whatever networking it
        already has; opt in explicitly if you want SapoHub to manage this.
        (lib.mkFreshMachine, the fresh-machine path, turns this on for you.)
      '';

      authKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to a file containing a Tailscale auth key (generate one at
          https://login.tailscale.com/admin/settings/keys). If present at
          activation, the autoconnect unit joins the tailnet unattended on
          first boot. If null (or the file doesn't exist yet), Tailscale is
          still enabled/started — join by hand once with
          `tailscale up` (prints a URL to approve in a browser). Either way
          it's a one-time per-machine step; state persists in
          /var/lib/tailscale across every future rebuild.
        '';
      };
    };

    nginx = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Run nginx in front of the app, listening on port 80 and
          proxying to the app's own port on 127.0.0.1. On by default so
          the app is reachable at `http://<host>` with no port in the
          URL. Also, whenever this is on, the app itself is switched to
          binding 127.0.0.1/::1 ONLY (BIND_IP=loopback) — nginx becomes
          the sole path in, there's no direct-port fallback reachable
          over Tailscale or any other interface. Set this to false if
          you want the app reachable directly on its own port instead
          (e.g. no nginx at all). Also the prerequisite for an
          (upcoming) dev-session proxy slots feature, which will add
          further nginx-fronted ports here (see sapo-hub v1's
          SapoHub.DevSessions / devSlots* options for the pattern that'll
          follow: fixed nginx-fronted external ports mapped to internal
          ports dev servers bind to).
        '';
      };

      https = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Also serve HTTPS on 443, using a cert Tailscale issues for
          this machine's MagicDNS name (via `tailscale cert`), kept
          fresh by a daily renewal timer (systemd unit
          sapohub-tailscale-cert). HTTP on 80 redirects to HTTPS once
          this is on.

          Two one-time prerequisites, neither doable from Nix/CLI:
            1. services.sapohub.tailscale.enable = true — the cert is
               issued for THIS machine's tailnet hostname, so it needs
               to actually be joined to one.
            2. "HTTPS Certificates" turned on for your tailnet, in the
               Tailscale admin console (DNS tab) — a manual, one-time,
               whole-tailnet setting.
          Until both are true, the renewal service's `tailscale cert`
          call keeps failing harmlessly (logged, not fatal) — nginx
          still starts and serves HTTPS with a self-signed placeholder
          cert (browsers will warn) until the real one is fetched.
        '';
      };
    };
  };

  config = mkIf cfg.enable (
    let
      storageRoot = if cfg.storageRoot != null then cfg.storageRoot else "${cfg.stateDir}/storage";
      workDir = if cfg.assistant.workDir != null then cfg.assistant.workDir else cfg.stateDir;
      bin = "${cfg.package}/bin/sapo_core";
      tlsDir = "/var/lib/sapohub-tls";
      tlsCertFile = "${tlsDir}/fullchain.pem";
      tlsKeyFile = "${tlsDir}/privkey.pem";
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

      # Nix-declared prefs base; the app overlays local UI edits on top.
      environment.etc."sapohub/prefs.json".text = builtins.toJSON cfg.prefs;

      systemd.services.sapohub = {
        description = "SapoHub 2.0";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        environment = {
          PHX_SERVER = "true";
          PHX_HOST = cfg.host;
          PORT = toString cfg.port;
          # nginx.enable means nginx is the sole path in — loopback-only,
          # no direct-port fallback on any external interface (Tailscale
          # included, despite tailscale0 being a trusted firewall
          # interface — trust doesn't matter if we're simply not
          # listening there).
          BIND_IP = if cfg.nginx.enable then "loopback" else "any";
          DATABASE_PATH = "${cfg.stateDir}/db/sapohub.db";
          STORAGE_ROOT = storageRoot;
          SNAPSHOTS_DIR = "${cfg.stateDir}/snapshots";
          RESTORE_PENDING = "${cfg.stateDir}/db/restore/pending.tar.gz";
          ASSISTANT_WORKDIR = workDir;
          ASSISTANT_CHROME = if cfg.assistant.browser.enable then "true" else "false";
          AGENT_NOTES = cfg.agentNotes;
          SAPO_CLI_PATH = "${cfg.cliPackage}/bin/sapo";
          PREFS_BASE = "/etc/sapohub/prefs.json";
          PREFS_OVERLAY = "${cfg.stateDir}/db/prefs-overlay.json";
          SAPO_API_BASE = "${baseUrl}/api";
          RELEASE_TMP = "${cfg.stateDir}/tmp";
          # The release store path is read-only; supply the node cookie
          # directly (single-node, value is irrelevant).
          RELEASE_COOKIE = "sapohub";
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

      # ── Optional: Tailscale + first-boot autoconnect ──────────────────────
      services.tailscale.enable = mkIf cfg.tailscale.enable true;
      networking.firewall.trustedInterfaces = mkIf cfg.tailscale.enable [ "tailscale0" ];

      systemd.services.tailscale-autoconnect = mkIf cfg.tailscale.enable {
        description = "Join the tailnet on first boot, if an authkey is present";
        after = [ "network-pre.target" "tailscale.service" ];
        wants = [ "network-pre.target" "tailscale.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig.Type = "oneshot";
        script = ''
          ${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' >/dev/null && exit 0
          if [ -n "${toString cfg.tailscale.authKeyFile}" ] && [ -f "${toString cfg.tailscale.authKeyFile}" ]; then
            ${pkgs.tailscale}/bin/tailscale up --auth-key "file:${toString cfg.tailscale.authKeyFile}"
          fi
        '';
      };

      # ── Optional: nginx in front of the app ────────────────────────────────
      # Listens on 80 (and 443 if nginx.https), proxies to the app's own
      # port on loopback. Whenever this is on, the app itself is bound
      # loopback-only (BIND_IP=loopback, set above) — nginx is the sole
      # path in, not an addition alongside a still-reachable app port.
      # Also gives future dev-session proxy slots a home in the same
      # vhost/service.
      services.nginx = mkIf cfg.nginx.enable {
        enable = true;
        recommendedProxySettings = true;
        recommendedGzipSettings = true;

        virtualHosts.${cfg.host} = {
          default = true;
          forceSSL = cfg.nginx.https;
          sslCertificate = mkIf cfg.nginx.https tlsCertFile;
          sslCertificateKey = mkIf cfg.nginx.https tlsKeyFile;
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.port}";
            proxyWebsockets = true;
          };
        };
      };

      # nginx.https needs SOME cert/key pair at tlsCertFile/tlsKeyFile
      # before nginx will even start — the real one only shows up once
      # sapohub-tailscale-cert (below) succeeds, which needs the box to
      # already be joined to a tailnet with HTTPS Certificates turned on.
      # Generate a short-lived self-signed placeholder here (idempotent —
      # only if missing) so nginx never fails to start on that account;
      # worst case is a browser warning until the real cert lands.
      #
      # MUST run via mkBefore, not mkAfter: NixOS's own nginx module
      # preStart ends with `nginx -t` (config test), which fails outright
      # if sslCertificate/sslCertificateKey don't exist on disk yet —
      # mkAfter would append this placeholder-generation AFTER that test
      # already failed, so nginx would never start. mkBefore runs it first.
      # nginx.service (including this preStart) runs as User=nginx, not
      # root — so both writers of this cert/key pair need to leave files
      # nginx itself can read. This one runs AS nginx, so files it creates
      # are already nginx:nginx by default; sapohub-tailscale-cert below
      # runs as root instead (it needs root to read tailscaled's socket),
      # so it explicitly chowns to nginx:nginx on write — see there.
      systemd.services.nginx.preStart = mkIf cfg.nginx.https (mkBefore ''
        mkdir -p ${tlsDir}
        if [ ! -s ${tlsCertFile} ] || [ ! -s ${tlsKeyFile} ]; then
          ${pkgs.openssl}/bin/openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout ${tlsKeyFile} -out ${tlsCertFile} -days 1 \
            -subj "/CN=${cfg.host}"
        fi
      '');

      # Fetches (and, on a timer, renews) the real cert Tailscale issues
      # for this machine's MagicDNS name. Never fatal if it fails — logs
      # why and leaves nginx on whatever cert it already had (placeholder
      # or a previous real one).
      systemd.services.sapohub-tailscale-cert = mkIf cfg.nginx.https {
        description = "Fetch/renew this machine's Tailscale HTTPS cert for nginx";
        after = [ "tailscaled.service" ];
        path = [ pkgs.tailscale pkgs.jq pkgs.coreutils ];
        serviceConfig.Type = "oneshot";
        script = ''
          dnsname="$(tailscale status --json | jq -r '.Self.DNSName // empty' | sed 's/\.$//')"
          if [ -z "$dnsname" ]; then
            echo "not joined to a tailnet yet (or DNSName unavailable) — skipping cert fetch"
            exit 0
          fi
          tmp="$(mktemp -d)"
          trap 'rm -rf "$tmp"' EXIT
          if tailscale cert --cert-file "$tmp/fullchain.pem" --key-file "$tmp/privkey.pem" "$dnsname"; then
            mkdir -p ${tlsDir}
            # This service runs as root (needs it to reach tailscaled's
            # socket), but nginx.service — the actual reader — runs as
            # User=nginx. Without an explicit chown these land root:root
            # and nginx can't open them, taking nginx down at its next
            # start/reload despite this fetch itself succeeding.
            install -m 600 -o nginx -g nginx "$tmp/fullchain.pem" ${tlsCertFile}
            install -m 600 -o nginx -g nginx "$tmp/privkey.pem" ${tlsKeyFile}
            systemctl reload nginx.service || true
            echo "renewed HTTPS cert for $dnsname"
          else
            echo "tailscale cert failed — is 'HTTPS Certificates' enabled for this tailnet? (admin console > DNS). nginx keeps using its previous/placeholder cert."
          fi
        '';
      };

      systemd.timers.sapohub-tailscale-cert = mkIf cfg.nginx.https {
        description = "Periodic Tailscale HTTPS cert renewal for nginx";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2m";
          OnUnitActiveSec = "24h";
          Persistent = true;
        };
      };
    }
  );
}
