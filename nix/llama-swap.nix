# mostlygeek/llama-swap — proxies one OpenAI+Anthropic-compatible endpoint in
# front of one or more llama.cpp/vLLM backends, hot-swapping which is loaded
# based on the `model` field of each request.
#
# go.mod requires go >= 1.26.1, so this MUST be built via `toolsPkgs`
# (nixpkgs-tools / nixos-unstable), not the project's pinned `nixpkgs` input —
# same reason tailwind_4 and yt-dlp are sourced from toolsPkgs in flake.nix.
{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "llama-swap";
  version = "244";

  src = fetchFromGitHub {
    owner = "mostlygeek";
    repo = "llama-swap";
    rev = "v${version}";
    hash = "sha256-y3BgH/9nze1ILsfHdHwT7cjJynFo6VFP2Ys3zBOZ478=";
  };

  vendorHash = "sha256-jQRnFGqQvk6my7ejnesv1pylCmEXLs9GKbQJEZdsaYg=";

  doCheck = false;

  meta = {
    description = "Proxy that hot-swaps llama.cpp/vLLM backends behind one OpenAI+Anthropic-compatible endpoint";
    homepage = "https://github.com/mostlygeek/llama-swap";
    license = lib.licenses.mit;
    mainProgram = "llama-swap";
  };
}
