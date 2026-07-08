# Fallback hardware configuration for the fresh-machine bootstrap target
# (nixosConfigurations.fresh-machine in flake.nix) when
# hardware/generated-hardware-configuration.nix hasn't been produced yet.
#
# DO NOT DEPLOY WITH THIS FILE — it's a placeholder so the flake evaluates
# (e.g. `nix flake check`) without a real target machine on hand.
#
# scripts/bootstrap.sh handles generating the real one automatically: it
# passes `--generate-hardware-config nixos-generate-config
# hardware/generated-hardware-configuration.nix` to nixos-anywhere, which
# boots the target into a NixOS installer environment, SSHes in, runs
# `nixos-generate-config` there, and copies the result back to that path
# before the actual install proceeds — this is what makes the fresh-machine
# path work on arbitrary hardware without you ever needing to hand-generate
# or commit a machine-specific config. See scripts/bootstrap.sh and the
# "Fresh machine" section of README.md.
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

  # Filesystem mounts are managed by disko (nix/disko-config.nix).

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
