# Parameterized disk layout. Lives in the TEMPLATE, not in emanix's lib/,
# because a disk layout is a fact about a machine and the distribution ships
# no machine facts.
{ host }:
let
  rootContent =
    if host.filesystem == "btrfs" then {
      type = "btrfs";
      extraArgs = [ "-f" ];
      subvolumes = {
        "@" = { mountpoint = "/"; mountOptions = [ "compress=zstd" ]; };
        "@nix" = { mountpoint = "/nix"; mountOptions = [ "compress=zstd" "noatime" ]; };
        "@home" = { mountpoint = "/home"; mountOptions = [ "compress=zstd" ]; };
      };
    } else {
      type = "filesystem";
      format = "ext4";
      mountpoint = "/";
    };

  # LUKS wraps the filesystem rather than replacing it, so the two knobs are
  # independent: ext4-on-LUKS and bare btrfs are both reachable.
  rootPartition =
    if host.luks then {
      type = "luks";
      name = "cryptroot";
      settings.allowDiscards = true;
      content = rootContent;
    } else rootContent;
in
_: {
  disko.devices.disk.main = {
    type = "disk";
    device = host.device;
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
      } // (if host.swapSize == "0" then { } else {
        swap = {
          size = host.swapSize;
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
