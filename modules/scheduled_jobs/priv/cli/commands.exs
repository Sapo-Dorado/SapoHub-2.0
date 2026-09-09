# SapoHub CLI commands: scheduled_jobs module (declarative — see SapoCliGen).
#
# Every action fits the declarative list/show/create/update/delete verbs
# (including "run", the empty-body manual trigger — same shape as
# tasks' complete/uncomplete) so no priv/cli/fragment.sh escape hatch is
# needed here.
[
  %{
    name: "scheduled-jobs",
    help:
      "list [--enabled true|false] | show <id> |
              create <name> --kind bash|prompt --command <cmd> --cron \"<expr>\"
                [--notify always|on_failure|never] [--destination <id>] [--timeout-ms <n>] |
              edit <id> [--name <n>] [--command <c>] [--cron <expr>]
                [--notify always|on_failure|never] [--destination <id>] [--timeout-ms <n>] |
              enable <id> | disable <id> | delete <id> | run <id>",
    actions: [
      %{action: "list", verb: :list, path: "/scheduled-jobs",
        params: [%{key: :enabled, flag: "--enabled"}]},
      %{action: "show", verb: :show, path: "/scheduled-jobs/:id"},
      %{action: "create", verb: :create, path: "/scheduled-jobs", args: [:name],
        params: [
          %{key: :kind, flag: "--kind", required: true},
          %{key: :command, flag: "--command", required: true},
          %{key: :cron, flag: "--cron", required: true},
          %{key: :notify_mode, flag: "--notify", default: "on_failure"},
          %{key: :notify_destination_id, flag: "--destination"},
          %{key: :timeout_ms, flag: "--timeout-ms", type: :integer}
        ]},
      %{action: "edit", verb: :update, path: "/scheduled-jobs/:id",
        params: [
          %{key: :name, flag: "--name"},
          %{key: :command, flag: "--command"},
          %{key: :cron, flag: "--cron"},
          %{key: :notify_mode, flag: "--notify"},
          %{key: :notify_destination_id, flag: "--destination"},
          %{key: :timeout_ms, flag: "--timeout-ms", type: :integer}
        ]},
      %{action: "enable", verb: :update, path: "/scheduled-jobs/:id",
        params: [%{key: :enabled, default: "true"}]},
      %{action: "disable", verb: :update, path: "/scheduled-jobs/:id",
        params: [%{key: :enabled, default: "false"}]},
      %{action: "delete", verb: :delete, path: "/scheduled-jobs/:id"},
      %{action: "run", verb: :create, path: "/scheduled-jobs/:id/run"}
    ]
  },
  %{
    name: "scheduled-jobs-runs",
    help: "list <job_id> | show <run_id>",
    actions: [
      %{action: "list", verb: :show, path: "/scheduled-jobs/:id/runs"},
      %{action: "show", verb: :show, path: "/scheduled-jobs/runs/:id"}
    ]
  }
]
