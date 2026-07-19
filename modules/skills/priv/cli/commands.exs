# SapoHub CLI commands: skills module (declarative — see SapoCliGen).
[
  %{
    name: "skills",
    help:
      "list | show <id> | add-marketplace <name> [--marketplace <m>] |
              register <name> | delete <id>",
    actions: [
      %{action: "list", verb: :list, path: "/skills"},
      %{action: "show", verb: :show, path: "/skills/:id"},
      %{
        action: "add-marketplace",
        verb: :create,
        path: "/skills/marketplace",
        args: [:name],
        params: [%{key: :marketplace, flag: "--marketplace", default: "claude-plugins-official"}]
      },
      %{action: "register", verb: :create, path: "/skills/custom", args: [:name]},
      %{action: "delete", verb: :delete, path: "/skills/:id"}
    ]
  }
]
