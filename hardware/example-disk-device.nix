# Fallback disk device used by `lib.mkFreshMachine` (flake.nix) for any
# hostname that doesn't yet have its own
# hardware/<hostname>-disk-device.nix (e.g. running `nix flake check`
# without ever having run scripts/bootstrap.sh against a real target, or
# bootstrapping a brand-new hostname for the first time).
# scripts/bootstrap.sh writes the real, per-hostname one — this file only
# exists so the flake evaluates cleanly before that.
{
  sapohubDiskDevice = "/dev/sda";
}
