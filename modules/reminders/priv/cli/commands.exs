# SapoHub CLI commands: reminders module (declarative — see SapoCliGen).
#
# Each entry becomes a `sapo <name> <action> ...` subcommand, generated
# into plain bash by `mix sapo.gen.cli`. Delete this file (and the
# priv/cli/ directory) if the module has no CLI commands.
#
# Supported verbs: :list, :show, :create, :update, :delete, :upload —
# see core/lib/mix/sapo_cli_gen.ex's moduledoc for the full spec format.
# If an action doesn't fit these verbs (a raw multipart request, a
# custom response shape, ...), leave it out here and instead define
# `sapo_cmd_reminders_ext()` in priv/cli/fragment.sh — the generated
# dispatcher's fallback arm calls it automatically.
#
[
  %{
    name: "reminders",
    help:
      "list [--status pending|sent|failed] | show <id> | create <message> --at YYYY-MM-DDTHH:MM:SS |
              update <id> [--message <m>] [--at <ts>] | cancel <id>",
    actions: [
      %{action: "list", verb: :list, path: "/reminders",
        params: [%{key: :status, flag: "--status"}]},
      %{action: "show", verb: :show, path: "/reminders/:id"},
      %{action: "create", verb: :create, path: "/reminders", args: [:message],
        params: [
          %{key: :remind_at, flag: "--at", required: true},
          %{key: :time_specific, flag: "--time-specific", type: :boolean, default: true}
        ]},
      %{action: "update", verb: :update, path: "/reminders/:id",
        params: [
          %{key: :message, flag: "--message"},
          %{key: :remind_at, flag: "--at"}
        ]},
      %{action: "cancel", verb: :delete, path: "/reminders/:id"}
    ]
  }
]
