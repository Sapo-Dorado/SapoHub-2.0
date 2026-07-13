# SapoHub CLI commands: hello module (declarative — see SapoCliGen).
[
  %{
    name: "hello",
    help: "list | create <name> | delete <id>",
    actions: [
      %{action: "list", verb: :list, path: "/hello"},
      %{action: "create", verb: :create, path: "/hello", args: [:name]},
      %{action: "delete", verb: :delete, path: "/hello/:id"}
    ]
  }
]
