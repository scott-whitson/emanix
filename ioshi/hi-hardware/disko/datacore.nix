{ ... }: {
  # Datacore (HP 15-ef2013dx, 1 TB NVMe) — headless server layout.
  # UNENCRYPTED by decision (2026-08-05 spec Q&A): the box must reboot
  # unattended; B2/restic is the encrypted copy. @srv-data is its own
  # subvolume so snapshots/quotas can treat service data separately, but
  # the MOUNTPOINT stays /home/srv-data — compose stacks bind-mount that
  # path verbatim (global constraint).
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1"; # verify against lsblk on the installer before running disko (Task 5)
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
        swap = {
          size = "16G";
          content = { type = "swap"; };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "@" = { mountpoint = "/"; mountOptions = [ "compress=zstd" ]; };
              "@nix" = { mountpoint = "/nix"; mountOptions = [ "compress=zstd" "noatime" ]; };
              "@home" = { mountpoint = "/home"; mountOptions = [ "compress=zstd" ]; };
              "@srv-data" = { mountpoint = "/home/srv-data"; mountOptions = [ "compress=zstd" ]; };
            };
          };
        };
      };
    };
  };
}
