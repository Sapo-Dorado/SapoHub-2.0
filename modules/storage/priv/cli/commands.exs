# SapoHub CLI commands: storage module (declarative — see SapoCliGen).
#
# Overrides core's base `sapo storage` (list/get/delete) the same way the
# old hand-written fragment.sh did — modules load after core, so redefining
# sapo_cmd_storage here simply replaces core's version when this module is
# enabled. `upload` isn't expressible as one of the standard verbs (it needs
# this module's own /storage/upload route), so it's added via the
# `_ext` escape hatch in priv/cli/fragment.sh instead of commands.exs.
[
  %{
    name: "storage",
    help: "list | get <path> [-o <file>] | delete <path> | upload <file>",
    actions: [
      %{action: "list", verb: :list, path: "/storage/files"},
      %{action: "get", verb: :show, path: "/storage/files/:id", output: true},
      %{action: "delete", verb: :delete, path: "/storage/files/:id"}
    ]
  }
]
