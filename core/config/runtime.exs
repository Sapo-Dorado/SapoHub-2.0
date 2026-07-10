import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/sapo_core start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :sapo_core, SapoCoreWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/sapo_core/sapo_core.db
      """

  config :sapo_core, SapoCore.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
    journal_mode: :wal,
    busy_timeout: 5000

  state_dir = Path.dirname(database_path)

  config :sapo_core,
    snapshots_dir: System.get_env("SNAPSHOTS_DIR") || Path.join(state_dir, "snapshots"),
    restore_pending:
      System.get_env("RESTORE_PENDING") || Path.join(state_dir, "restore/pending.tar.gz"),
    # Written by sapohub-deploy (nix/deploy-script.nix) from inside its
    # detached rebuild unit, independent of this app's own process
    # lifecycle — read at Settings-page mount time to show "last deployed
    # at" + success/failure even across a sapohub.service restart or a
    # page reload.
    last_deploy_file:
      System.get_env("LAST_DEPLOY_FILE") || Path.join(state_dir, "last-deploy.json"),
    # `--sync-prefs` opts in to writing the local UI-preference overlay back
    # into the config repo. Only the Settings "Deploy" button should do this
    # (see nix/deploy-script.nix) — a bare `sudo sapohub-deploy` run by hand
    # (SSH, cron, whatever) must leave git/nix as the sole source of truth.
    deploy_cmd: {"sudo", [System.get_env("DEPLOY_BIN") || "sapohub-deploy", "--sync-prefs"]},
    # Companion to sapohub-deploy (nix/secret-script.nix): writes one line
    # of the root-only secrets file at a time, restricted to a fixed
    # allowlist baked in at build time. Value is always piped over stdin
    # by the caller (settings_live.ex), never argv.
    set_secret_cmd: {"sudo", [System.get_env("SET_SECRET_BIN") || "sapohub-set-secret"]}

  storage_root =
    System.get_env("STORAGE_ROOT") ||
      raise """
      environment variable STORAGE_ROOT is missing.
      For example: /var/lib/sapohub/storage
      """

  config :sapo_core, storage_root: storage_root

  # Assistant session working directory (nix option assistant.workDir).
  if workdir = System.get_env("ASSISTANT_WORKDIR") do
    config :sapo_core, assistant_workdir: workdir
  end

  # Whether assistant sessions get --chrome (nix option assistant.browser.enable).
  config :sapo_core, assistant_chrome: System.get_env("ASSISTANT_CHROME") == "true"

  # Free-form agent notes for the AI context (nix option agentNotes),
  # one note per line.
  config :sapo_core, agent_notes: System.get_env("AGENT_NOTES")

  # Absolute path of the composed sapo CLI (set by the nix module) so the
  # AI context can embed `sapo --help`.
  config :sapo_core, sapo_cli_path: System.get_env("SAPO_CLI_PATH")

  # UI prefs: nix-declared base + instantly-editable local overlay
  # (synced back into the config repo by sapohub-deploy).
  config :sapo_core,
    prefs_base: System.get_env("PREFS_BASE"),
    prefs_overlay: System.get_env("PREFS_OVERLAY") || Path.join(state_dir, "prefs-overlay.json")

  # Core secrets validated as hard boot requirements by SapoCore.Secrets.
  # SECRET_KEY_BASE / DATABASE_PATH already raise above; list any further
  # core-owned env vars here.
  config :sapo_core, core_secrets: []

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  # BIND_IP=loopback restricts the app to 127.0.0.1/::1 — set by the NixOS
  # module whenever services.sapohub.nginx.enable is true, so nginx is the
  # only path in (over Tailscale or otherwise) and the app's own port never
  # answers on any external interface. Defaults to all-interfaces, matching
  # the Phoenix generator default, for anyone running without nginx in front.
  bind_ip =
    case System.get_env("BIND_IP") do
      "loopback" -> {0, 0, 0, 0, 0, 0, 0, 1}
      _ -> {0, 0, 0, 0, 0, 0, 0, 0}
    end

  config :sapo_core, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # check_origin defaults to comparing the socket's Origin header against
  # url: [host: ...] above — fine for a fixed domain, but wrong whenever
  # the real access hostname isn't knowable at build time (e.g. a
  # Tailscale MagicDNS name assigned at join time). CHECK_ORIGIN (set by
  # the nix module when services.sapohub.tailscale.enable is true) widens
  # this to a comma-separated list of Phoenix check_origin patterns
  # instead, e.g. "//*.ts.net". Unset/empty falls back to the default
  # host-based check, matching prior behavior.
  check_origin =
    case System.get_env("CHECK_ORIGIN") do
      origins when origins in [nil, ""] -> true
      origins -> String.split(origins, ",")
    end

  config :sapo_core, SapoCoreWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: check_origin,
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: bind_ip,
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :sapo_core, SapoCoreWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :sapo_core, SapoCoreWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
