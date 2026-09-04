# SapoHub CLI commands: subscriptions module (declarative — see SapoCliGen).
[
  %{
    name: "subscriptions",
    help:
      "list | create <name> <cost> [--every <n>] [--unit month|year] [--notes <text>] | edit <id> [--name <n>] [--cost <c>] [--every <n>] [--unit month|year] [--notes <n>] | delete <id>",
    actions: [
      %{action: "list", verb: :list, path: "/subscriptions"},
      %{
        action: "create",
        verb: :create,
        path: "/subscriptions",
        args: [:name, :cost],
        params: [
          %{key: :interval_count, flag: "--every", default: "1", type: :integer},
          %{key: :interval_unit, flag: "--unit", default: "month"},
          %{key: :notes, flag: "--notes", default: ""}
        ]
      },
      %{
        action: "edit",
        verb: :update,
        path: "/subscriptions/:id",
        params: [
          %{key: :name, flag: "--name"},
          %{key: :cost, flag: "--cost"},
          %{key: :interval_count, flag: "--every", type: :integer},
          %{key: :interval_unit, flag: "--unit"},
          %{key: :notes, flag: "--notes"}
        ]
      },
      %{action: "delete", verb: :delete, path: "/subscriptions/:id"}
    ]
  }
]
