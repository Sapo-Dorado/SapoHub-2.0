# Builds the llama-swap package + renders its YAML config from
# services.sapohub.assistant.localModels.{models,groups}. Consumed by
# nixos-module.nix, which defines the actual systemd unit and env wiring —
# this file only produces the pieces that unit needs.
#
# `groups` (llama-swap's concurrent-warm-set feature) is intentionally NOT
# rendered here yet: current llama-swap (v244+) replaced the simple
# swap/members `groups:` key with a solver-based `matrix:` DSL, and the exact
# translation from this module's simpler `groups` option hasn't been verified
# against that DSL. nixos-module.nix asserts `groups == {}` until that's done.
{ pkgs, lib, toolsPkgs }:
{ models }:

let
  llamaCpp = toolsPkgs.llama-cpp;

  yamlFormat = pkgs.formats.yaml { };

  # ${PORT} is llama-swap's OWN macro (auto-incremented from its startPort,
  # one per model) — passed through as a literal string, not Nix-interpolated.
  renderModel = _name: m:
    {
      cmd = lib.concatStringsSep " " ([
        "${llamaCpp}/bin/llama-server"
        "--model" m.weightsPath
        "--port"
        "\${PORT}"
        "--ctx-size"
        (toString m.contextSize)
      ] ++ m.extraArgs);
    }
    // lib.optionalAttrs (m.ttl != null) { inherit (m) ttl; };

  renderedConfig = {
    models = lib.mapAttrs renderModel models;
  };

  configFile = yamlFormat.generate "llama-swap-config.yaml" renderedConfig;
in
{
  package = toolsPkgs.callPackage ./llama-swap.nix { };
  inherit configFile;
}
