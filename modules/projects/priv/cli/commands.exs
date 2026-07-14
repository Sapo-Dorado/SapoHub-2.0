# SapoHub CLI commands: projects module (declarative — see SapoCliGen).
#
# `list`/`show`/`create`/`delete` map to standard verbs. Everything
# script-related (listing runnable scripts, running one with param
# overrides) and param upsert/delete needs its own request shape and isn't
# expressible as a standard verb, so it's added via the `_ext` escape
# hatch in priv/cli/fragment.sh instead.
[
  %{
    name: "projects",
    help: "list | show <id> | create <name> <github_url> | delete <id>",
    actions: [
      %{action: "list", verb: :list, path: "/projects"},
      %{action: "show", verb: :show, path: "/projects/:id"},
      %{action: "create", verb: :create, path: "/projects", args: [:name, :github_url]},
      %{action: "delete", verb: :delete, path: "/projects/:id"}
    ]
  }
]
