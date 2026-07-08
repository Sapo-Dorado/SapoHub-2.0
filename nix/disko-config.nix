# Disk layout for a fresh-machine bootstrap via nixos-anywhere (disko module).
#
# GPT + BIOS boot + swap + ext4 root — same layout SapoHub v1 used, picked
# for being the simplest thing that works across the widest range of VMs
# and bare metal without needing to know in advance whether the target
# boots UEFI or legacy BIOS (GRUB with efiSupport=false works either way
# on x86_64; see the fresh-machine nixosConfigurations block in flake.nix).
#
# The target disk device varies per machine (/dev/sda, /dev/vda,
# /dev/nvme0n1, ...), so it isn't hardcoded here. scripts/bootstrap.sh
# writes it to hardware/generated-disk-device.nix (gitignored, regenerated
# every bootstrap run) before invoking nixos-anywhere; that file just sets
# `sapohubDiskDevice`, imported below. Falls back to /dev/sda if you're
# evaluating this module without having run the bootstrap script (e.g.
# `nix flake check`) — see hardware/example-disk-device.nix.
{ lib, ... }:

let
  generated = ../hardware/generated-disk-device.nix;
  example = ../hardware/example-disk-device.nix;
  diskDeviceModule = if builtins.pathExists generated then generated else example;
  inherit (import diskDeviceModule) sapohubDiskDevice;
in
{
  disko.devices.disk.main = {
    device = sapohubDiskDevice;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        swap = {
          size = "2G";
          content.type = "swap";
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
