# Fallback hardware configuration used by `lib.mkFreshMachine` (flake.nix)
# for any hostname that doesn't yet have its own
# hardware/<hostname>-hardware-configuration.nix.
#
# DO NOT DEPLOY WITH THIS FILE — it's a placeholder so the flake evaluates
# (e.g. `nix flake check`) without a real target machine on hand.
#
# scripts/bootstrap.sh generates the real, per-hostname one automatically:
# it passes `--generate-hardware-config nixos-generate-config
# hardware/<hostname>-hardware-configuration.nix` to nixos-anywhere, which
# boots the target into a NixOS installer environment, SSHes in, runs
# `nixos-generate-config` there, and copies the result back to that path
# before the actual install proceeds, then (by default) commits it into
# the config repo — this is what makes the fresh-machine path work on
# arbitrary hardware without you ever needing to hand-generate a
# machine-specific config, while still keeping each host's real config
# around for future redeploys. See scripts/bootstrap.sh and the "Fresh
# machine" section of README.md.
{ lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
  ];

  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # Filesystem mounts are managed by disko (see lib.mkFreshMachine in
  # flake.nix, and hardware/<hostname>-disk-device.nix for the device).

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
