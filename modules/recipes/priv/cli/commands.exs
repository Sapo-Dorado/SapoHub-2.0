# SapoHub CLI commands: recipes module (declarative — see SapoCliGen).
#
# Bulk/secondary actions (clear-checked, removing a single contribution,
# renaming/deleting an ingredient's usage details) are left to the UI —
# this covers the day-to-day verbs: browsing recipes, and adding/checking
# off shopping-list items.
[
  %{
    name: "recipes",
    help: "list [--q <query>] | show <id> | create <name> [--directions <text>] | delete <id>",
    actions: [
      %{action: "list", verb: :list, path: "/recipes", params: [%{key: :q, flag: "--q"}]},
      %{action: "show", verb: :show, path: "/recipes/:id"},
      %{action: "create", verb: :create, path: "/recipes", args: [:name],
        params: [%{key: :directions, flag: "--directions", default: ""}]},
      %{action: "delete", verb: :delete, path: "/recipes/:id"}
    ]
  },
  %{
    name: "ingredients",
    help: "list [--q <query>] | create <name> | rename <id> <name> | delete <id>",
    actions: [
      %{action: "list", verb: :list, path: "/recipes/ingredients", params: [%{key: :q, flag: "--q"}]},
      %{action: "create", verb: :create, path: "/recipes/ingredients", args: [:name]},
      %{action: "rename", verb: :update, path: "/recipes/ingredients/:id", args: [:name]},
      %{action: "delete", verb: :delete, path: "/recipes/ingredients/:id"}
    ]
  },
  %{
    name: "shopping-list",
    help: "list | add <ingredient_id> [--note <text>] | check <id> | uncheck <id> | delete <id>",
    actions: [
      %{action: "list", verb: :list, path: "/recipes/shopping-list"},
      %{action: "add", verb: :create, path: "/recipes/shopping-list/items", args: [:ingredient_id],
        params: [%{key: :note, flag: "--note"}]},
      %{action: "check", verb: :create, path: "/recipes/shopping-list/items/:id/check"},
      %{action: "uncheck", verb: :create, path: "/recipes/shopping-list/items/:id/uncheck"},
      %{action: "delete", verb: :delete, path: "/recipes/shopping-list/items/:id"}
    ]
  }
]
