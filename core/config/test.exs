import Config

# Module file storage root (dirs auto-created at boot).
config :sapo_core, storage_root: Path.expand("../tmp/storage_test", __DIR__)

config :sapo_core,
  snapshots_dir: Path.expand("../tmp/snapshots_test", __DIR__),
  restore_pending: Path.expand("../tmp/restore_test/pending.tar.gz", __DIR__),
  deploy_cmd: {"bash", ["-lc", "echo deploy-stub"]},
  set_secret_cmd:
    {"bash",
     [
       "-lc",
       ~s'if [ "$1" = --status ]; then echo missing; else IFS= read -r _; echo ok; fi',
       "--"
     ]}

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :sapo_core, SapoCore.Repo,
  database: Path.expand("../sapo_core_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sapo_core, SapoCoreWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "vIeTHpOal9oaDnU9QWgK+fPOli/TRRqU/54/CjiDKWEXSeTwrbzLqarTvac2oLZa",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :sapo_core, prefs_overlay: Path.expand("../tmp/prefs_overlay_test.json", __DIR__)

# skills module: isolate ~/.claude equivalent from the real box's HOME
# (its boot reconcile task manages a real symlink + reads/writes real
# `claude` CLI state otherwise), and never shell out to the real `claude`
# binary during tests (no network, deterministic, no mutation of real
# installed plugins).
config :skills,
  claude_home: Path.expand("../tmp/claude_home_test", __DIR__),
  enable_claude_cli: false
