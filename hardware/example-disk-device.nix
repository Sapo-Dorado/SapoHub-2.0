# Fallback disk device for nix/disko-config.nix when
# hardware/generated-disk-device.nix hasn't been produced yet (e.g. running
# `nix flake check` without ever having run scripts/bootstrap.sh against a
# real target). scripts/bootstrap.sh writes the real one — this file only
# exists so the flake evaluates cleanly before that.
{
  sapohubDiskDevice = "/dev/sda";
}
