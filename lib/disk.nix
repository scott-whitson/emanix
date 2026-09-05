# The emanix disk layout, parameterized.
#
# Promoted out of templates/default/disko.nix, which is where it lived while
# the only consumer was a generated host. It is the DISTRIBUTION's opinion
# about how a disk should be laid out — an ESP at /boot, optional swap, one
# root partition, btrfs subvolumes, optionally wrapped in LUKS. What machine
# it is applied to stays the consumer's fact: this function takes `device`
# rather than knowing one.
#
# Returns a NixOS MODULE (a function ignoring its argument), so a consumer can
# drop the result straight into a module list beside disko.nixosModules.disko.
#
# LUKS wraps the filesystem rather than replacing it, so the two knobs are
# independent: ext4-on-LUKS and bare btrfs are both reachable.
{ device
, luks ? false
, filesystem ? "btrfs"
, swapSize ? "0"
, extraSubvolumes ? { }
}:
let
  baseSubvolumes = {
    "@" = { mountpoint = "/"; mountOptions = [ "compress=zstd" ]; };
    "@nix" = { mountpoint = "/nix"; mountOptions = [ "compress=zstd" "noatime" ]; };
    "@home" = { mountpoint = "/home"; mountOptions = [ "compress=zstd" ]; };
  };

  rootContent =
    if filesystem == "btrfs" then {
      type = "btrfs";
      extraArgs = [ "-f" ];
      # extraSubvolumes wins on a key collision, so a consumer can retune "@"
      # rather than only add beside it.
      subvolumes = baseSubvolumes // extraSubvolumes;
    } else {
      type = "filesystem";
      format = "ext4";
      mountpoint = "/";
    };

  rootPartition =
    if luks then {
      type = "luks";
      name = "cryptroot";
      settings.allowDiscards = true;
      content = rootContent;
    } else rootContent;
in
_: {
  disko.devices.disk.main = {
    type = "disk";
    inherit device;
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "fmask=0077" "dmask=0077" ];
          };
        };
      } // (if swapSize == "0" then { } else {
        swap = {
          size = swapSize;
          content = { type = "swap"; };
        };
      }) // {
        root = {
          size = "100%";
          content = rootPartition;
        };
      };
    };
  };
}
