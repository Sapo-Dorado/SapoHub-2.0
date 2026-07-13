# SapoHub CLI commands: my_plate module (declarative — see SapoCliGen).
[
  %{
    name: "tasks",
    help:
      "list [--priority high|medium|low] | show <id> | create <title> [--priority <p>] [--due YYYY-MM-DD] |
              complete <id> | uncomplete <id> | delete <id>",
    actions: [
      %{action: "list", verb: :list, path: "/tasks",
        params: [%{key: :priority, flag: "--priority"}]},
      %{action: "show", verb: :show, path: "/tasks/:id"},
      %{action: "create", verb: :create, path: "/tasks", args: [:title],
        params: [
          %{key: :priority, flag: "--priority", default: "medium"},
          %{key: :due_date, flag: "--due"}
        ]},
      %{action: "complete", verb: :create, path: "/tasks/:id/complete"},
      %{action: "uncomplete", verb: :create, path: "/tasks/:id/uncomplete"},
      %{action: "delete", verb: :delete, path: "/tasks/:id"}
    ]
  },
  %{
    name: "recurring",
    help:
      "list | create <title> --recurrence daily|weekly|monthly [--priority <p>]
              [--day-of-week 1-7] [--day-of-month 1-31] | delete <id>",
    actions: [
      %{action: "list", verb: :list, path: "/recurring-tasks"},
      %{action: "create", verb: :create, path: "/recurring-tasks", args: [:title],
        params: [
          %{key: :priority, flag: "--priority", default: "medium"},
          %{key: :recurrence, flag: "--recurrence", required: true},
          %{key: :day_of_week, flag: "--day-of-week", type: :integer},
          %{key: :day_of_month, flag: "--day-of-month", type: :integer}
        ]},
      %{action: "delete", verb: :delete, path: "/recurring-tasks/:id"}
    ]
  }
]
