# SapoHub CLI commands: core-owned resources (declarative — see SapoCliGen).
#
# Unlike a module's priv/cli/commands.exs (discovered via the modules lock
# file), this one is generated directly into priv/cli/core.sh's assembly by
# `mix sapo.gen.cli` — see that task's run/1. No `help:` fields are set
# below since these resources are already documented in core.sh's
# hand-written sapo_help() "Core:" section.
#
# `notify` is NOT here — it's a flat `sapo notify <message> [flags]`
# command with no action word, which doesn't fit this generator's
# <resource> <action> model, so it stays hand-written in core.sh.

[
  %{
    name: "destinations",
    actions: [
      %{action: "list", verb: :list, path: "/notification-destinations"},
      %{
        action: "create",
        verb: :create,
        path: "/notification-destinations",
        args: [:name, :channel],
        params: [%{key: :config, flag: "--config", type: :json, default: "{}"}]
      },
      %{action: "delete", verb: :delete, path: "/notification-destinations/:id"},
      %{
        action: "set-default",
        verb: :create,
        path: "/notification-destinations/:id/set-default"
      }
    ]
  }
]
