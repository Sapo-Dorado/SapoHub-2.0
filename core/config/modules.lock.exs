# Enabled util modules: {otp_app, source_path} pairs consumed by mix.exs.
# Relative paths are resolved against this file's directory.
#
# This checked-in version is the DEV default. In a Nix-composed release
# build, Nix generates this file (pointing at /nix/store paths) together
# with lib/sapo_core/generated/registry.ex — the two must stay in sync.
[
  {:sapo_hello, "../../modules/hello"}
]
