{ ... }: {
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
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
        root = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings.allowDiscards = true;
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@" = { mountpoint = "/"; mountOptions = [ "compress=zstd" ]; };
                "@nix" = { mountpoint = "/nix"; mountOptions = [ "compress=zstd" "noatime" ]; };
                "@home" = { mountpoint = "/home"; mountOptions = [ "compress=zstd" ]; };
              };
            };
          };
        };
      };
    };
  };
}
