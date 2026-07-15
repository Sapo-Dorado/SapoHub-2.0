# SapoHub CLI commands: projects module (declarative — see SapoCliGen).
#
# `list`/`show`/`create`/`delete`/`sync`/`push` map to standard verbs (a
# bare POST to a path, same shape as e.g. destinations' `set-default` in
# core's own commands.exs). Everything script-related (listing runnable
# scripts, running one with param overrides) and param upsert/delete
# needs its own request shape and isn't expressible as a standard verb,
# so it's added via the `_ext` escape hatch in priv/cli/fragment.sh
# instead.
[
  %{
    name: "projects",
    help: "list | show <id> | create <name> <github_url> | delete <id> | sync <id> | push <id>",
    actions: [
      %{action: "list", verb: :list, path: "/projects"},
      %{action: "show", verb: :show, path: "/projects/:id"},
      %{action: "create", verb: :create, path: "/projects", args: [:name, :github_url]},
      %{action: "delete", verb: :delete, path: "/projects/:id"},
      %{action: "sync", verb: :create, path: "/projects/:id/sync"},
      %{action: "push", verb: :create, path: "/projects/:id/push"}
    ]
  }
]
