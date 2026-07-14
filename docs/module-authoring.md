# Writing a SapoHub Utility Module

A utility module is a standalone Mix project with exactly ONE dependency:
`:sapo_module_kit` (the contract package). Core discovers everything about
your module through one `SapoKit.Module` implementation, and your module
reaches all shared functionality through `SapoKit.*` facades.

**The golden rule: utilities are completely independent of each other.**
Your module never calls another module and never exposes an API to one.
If you need something another module would also need — notifications,
storage, scheduling, HTTP — it's a core service (below). If a core service
is missing something, extend core; don't couple modules.

The `modules/hello` module is the living example: every callback a real
module might override is exercised somewhere in its source tree. Generate
a fresh skeleton with:

    mix sapo.gen.module my_thing

## Project shape

```
my_thing/
├── mix.exs                      # deps: [{:sapo_module_kit, ...}] only
├── lib/
│   ├── my_thing/
│   │   ├── module.ex            # the SapoKit.Module implementation
│   │   ├── my_thing.ex          # your context (business logic)
│   │   └── thing.ex             # Ecto schemas (use SapoKit.Schema)
│   └── my_thing_web/
│       ├── live/index.ex        # LiveViews (use SapoKit.Web, :live_view)
│       └── api/things_controller.ex
├── priv/
│   ├── migrations/              # full-timestamp versions, prefixed tables
│   └── cli/fragment.sh          # optional `sapo <resource>` subcommands (M4)
└── assets/hooks.js              # optional LiveView JS hooks (framework-free)
```

Enabled modules are composed by Nix in production; in dev they come from
`core/config/modules.lock.exs` + `core/lib/sapo_core/generated/registry.ex`
(keep the two in sync).

## The module contract (`use SapoKit.Module`)

Only `id/0` and `title/0` are required; everything else has a no-op default.

| Callback | Default | Purpose |
|---|---|---|
| `id()` | — | Unique atom, e.g. `:my_thing`. Config key + table-name prefix. |
| `title()` | — | Human name for UI + snapshot manifest. |
| `version()` | app vsn | Recorded in snapshot manifests. |
| `icon()` | generic | Heroicon name for the default dashboard button. |
| `dashboard_buttons(config)` | `[]` | Extra dashboard button VARIANTS (LiveComponents in the fixed-size slot). The default icon+title button is free; the user picks the variant in Settings. |
| `statusline_items(config)` | `[]` | `%SapoKit.StatuslineItem{}` segments for the global statusline (text/level fns + PubSub `topics` for live updates). User-toggleable. |
| `settings_component()` | `nil` | LiveComponent rendered as your own tab on the Settings page. |
| `ui_routes()` | `[]` | LiveView routes, absolute paths (`/my-thing`). Mounted in the ONE shared `live_session` (use `<.link navigate>`). |
| `api_routes()` | `[]` | JSON routes relative to `/api`. |
| `migrations_path()` | `priv/migrations` | Run at boot/deploy together with core's. |
| `scheduler_hooks()` | `[]` | Recurring work (see Scheduling). |
| `children(config)` | `[]` | GenServers added to core's supervision tree. |
| `storage_paths()` | `[]` | **Storage opt-in.** `[]` = no storage dir. Non-empty = dedicated dir + these subdirs (`["."]` = just the dir). |
| `required_secrets()` | `[]` | Env var names; missing ones warn at boot + show in Settings. Degrade gracefully. |
| `ai_context()` | `nil` | Markdown fragment for `/api/claude-context`; embed your own live counts. |
| `assistant_system_prompt()` | `nil` | Short fragment appended to the assistant's system prompt at session start (rules/pointers, not data). |
| `config_schema()` | `[]` | NimbleOptions schema; nix-provided config is validated against it at boot (fail fast). |

Runtime config access outside callback arguments (contexts, hooks):
`SapoKit.ModuleConfig.get(:my_thing, :some_key)`.

Route rules: core reserves UI paths `/`, `/settings`, `/assistant` and API
paths `/claude-context`, `/snapshot`, `/notify`,
`/notification-destinations`, `/storage/files`. Collisions (with core or
another module) fail the build with both module names.

## Core services (the `SapoKit.*` facades)

### Database — `SapoKit.Repo`
Delegates to core's SQLite repo. Prefix your tables with your module id
(`my_thing_items`), and `use SapoKit.Schema` for binary ids. SQLite
notes: keep write transactions short.

Generate migrations with `mix sapo.gen.migration create_my_thing_items`
(from `sapo_module_kit`, so every module has it) instead of
`mix ecto.gen.migration` — it versions the file as
`<timestamp><3-digit-module-tag>` instead of a bare timestamp, so two
modules picking the same second (or copy-pasting a template migration
without editing it) can't collide even by accident. `SapoCore.Release`
still asserts version uniqueness at boot as a backstop, but with this
task the versions are namespaced by module identity from the start.

### PubSub — `SapoKit.PubSub`
`subscribe/1`, `broadcast/2` on core's PubSub. Broadcast on state changes —
this is also what will drive live statusline/dashboard updates.

### Notifications — `SapoKit.Notify`
```elixir
SapoKit.Notify.send("Task 'water plants' is due")
SapoKit.Notify.send("Chart ready", image: "/path/on/server.png")
SapoKit.Notify.send("...", destination_id: id)   # instead of the default
```
Destinations (telegram/discord) are configured by the USER in Settings /
API — modules never touch destination config. Handle `{:error,
:no_destination}` gracefully.

### One-shot scheduling — `SapoKit.Scheduler` + `SapoKit.Scheduler.Handler`
Run something once at a specific time (survives restarts):
```elixir
defmodule MyThing.PingHandler do
  @behaviour SapoKit.Scheduler.Handler
  @impl true
  def handle_scheduled(%{"item_id" => id}) do
    # idempotent! may fire late (downtime catch-up) or be retried
    SapoKit.Notify.send("Ping for item #{id}")
  end
end

SapoKit.Scheduler.schedule_at(at, MyThing.PingHandler, %{item_id: item.id},
  source: :my_thing, ref: item.id)
SapoKit.Scheduler.cancel_scheduled(:my_thing, item.id)
SapoKit.Scheduler.reschedule(:my_thing, item.id, new_at)
```
Payloads round-trip through JSON — handlers receive STRING keys. `:ok`
deletes the action; anything else (or a crash) keeps it for retry next tick.

### Recurring scheduling — `SapoKit.Scheduler.Hook`
For periodic work, declare hooks in `scheduler_hooks()`:
```elixir
defmodule MyThing.HourlySweep do
  @behaviour SapoKit.Scheduler.Hook
  def hook_id, do: "my_thing.sweep"
  def next_run_at(nil, now), do: now
  def next_run_at(last, _now), do: DateTime.add(last, 3600, :second)
  def run(now), do: MyThing.sweep(now)   # :ok advances last_run_at
end
```
**Catch-up is YOUR responsibility**: when due, `run/1` is called ONCE even
if many slots were missed — derive the whole gap's work from your data and
make it idempotent. The scheduler guarantees: no self-overlap, retries on
failure/crash, `last_run_at` persisted across restarts. Precise timing
needs? Use `children/1` with your own GenServer instead.

### Storage — `SapoKit.Storage` (opt-in)
Declare `storage_paths()` (non-empty) to get a dedicated directory:
```elixir
def storage_paths, do: ["exports"]        # dir + exports/ subdir
# or  ["."]                               # just the dir

dir = SapoKit.Storage.dir(:my_thing)      # created at boot
File.write!(SapoKit.Storage.path(:my_thing, "exports/report.csv"), csv)
```
The filesystem is the source of truth: files appear in `GET
/api/storage/files`, are downloadable/deletable there, and are included in
snapshots. No opt-in → no directory, and the file API refuses the path.

### HTTP — `SapoKit.HTTP`
```elixir
{:ok, %{status: 200, body: body}} = SapoKit.HTTP.get(url)
SapoKit.HTTP.post(url, json: %{...})
```
One shared pool for the hub; options are Req options. Don't add HTTP client
deps to your module.

### Secrets
Declare `required_secrets: ["MY_THING_TOKEN"]`, read with `System.get_env/1`
at call time. Missing secrets warn at boot and surface in Settings; your
module must still boot and degrade gracefully.

### Web building blocks — `SapoKit.Web`, `SapoKit.Layouts`
`use SapoKit.Web, :live_view` / `:controller` give you LiveView/controller
scaffolding wired to core's layouts, plus `SapoKit.Web.ApiHelpers`
(`render_changeset_errors/2`, `render_not_found/1`).

### AI context
Return a markdown fragment from `ai_context()` describing your module for
AI agents: what it does, its API routes/CLI, current live counts. It is
served from `GET /api/claude-context` alongside every other module's.

## Testing

Core's test suite boots with the modules in `modules.lock.exs`. Pattern:
drive the scheduler with `tick_ms: :manual` + an injected `now_fun`, stub
HTTP via `config :sapo_core, :http_client` (see `SapoCore.FakeHTTP`), and
test your context directly against `SapoKit.Repo`.

## Checklist before shipping

- [ ] `id`, `title`, routes, migrations prefixed with your module id
- [ ] no deps besides `:sapo_module_kit`; HTTP via `SapoKit.HTTP`
- [ ] no calls into any other utility module
- [ ] scheduler hooks handle catch-up idempotently
- [ ] storage only if opted in; secrets declared; graceful degradation
- [ ] `ai_context()` written; `config_schema()` covers your nix options
