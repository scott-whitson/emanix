# The emanix disk layout, parameterized.
#
# The DISTRIBUTION's opinion about how a disk should be laid out — an ESP at
# /boot, optional swap, one root partition, btrfs subvolumes, optionally wrapped
# in LUKS. Which machine it is applied to stays the consumer's fact: this takes
# `device` rather than knowing one.
#
# Returns a NixOS MODULE (a function ignoring its argument), so a consumer drops
# the result straight into a module list beside disko.nixosModules.disko.
#
# LUKS wraps the filesystem rather than replacing it, so the two knobs are
# independent: ext4-on-LUKS and bare btrfs are both reachable.
#
# The two asserts below validate the arguments at EVALUATION rather than leaving
# it to the installer prompt. fresh-emanix-install validates its own answers, but
# it is not the only caller: the template tells the operator to edit host.nix by
# hand, and a consuming flake calls mkDisk directly with no prompt in sight. disko
# runs destroy BEFORE format, so anything that only fails at format time fails
# with the disk already wiped — the difference between a typo and an unbootable
# machine. `|| throw` rather than a bare assert, because a bare assert prints the
# failing expression and for builtins.match that is unreadable.
{ device
, luks ? false
, filesystem ? "btrfs"
, swapSize ? "0"
, extraSubvolumes ? { }
}:
let
  # A local `lib.recursiveUpdate`, inlined rather than taken as an argument.
  #
  # This file is `import`ed directly by the flake (`lib.mkDisk`), by the
  # template's flake.nix and by checks/template-host.nix, none of which have a
  # `lib` to hand — mkDisk's argument set IS its public signature, and adding a
  # `lib` parameter (even an optional one) would put a nixpkgs-shaped thing in
  # a signature that is otherwise five plain values. Defaulting it from
  # `import <nixpkgs> {}` would be worse: it makes a pure function depend on
  # NIX_PATH, and the disk layout is the last place to introduce impurity.
  # Six lines of merge is the cheaper of the two prices. Semantics match
  # nixpkgs' recursiveUpdate exactly: recurse where both sides are attrsets,
  # otherwise the right-hand side wins.
  recursiveUpdate = lhs: rhs:
    lhs // builtins.mapAttrs
      (name: rval:
        let lval = lhs.${name} or null; in
        if builtins.isAttrs lval && builtins.isAttrs rval
        then recursiveUpdate lval rval
        else rval)
      rhs;

  baseSubvolumes = {
    "@" = { mountpoint = "/"; mountOptions = [ "compress=zstd" ]; };
    "@nix" = { mountpoint = "/nix"; mountOptions = [ "compress=zstd" "noatime" ]; };
    "@home" = { mountpoint = "/home"; mountOptions = [ "compress=zstd" ]; };
  };

  rootContent =
    if filesystem == "btrfs" then {
      type = "btrfs";
      extraArgs = [ "-f" ];
      # extraSubvolumes wins PER LEAF, so a consumer can retune "@" rather than
      # only add beside it. It is a recursive merge and not `//` on purpose:
      # `//` replaces the whole "@" attrset, so a consumer retuning only
      # mountOptions would silently drop `mountpoint = "/"`. disko would then
      # create the subvolume, mount nothing at /, and nixos-install would fail
      # with "The `fileSystems' option does not specify your root file system"
      # — after destroy and format. tests/disk-layout.sh has a collision case
      # for exactly this.
      #
      # Identical to `//` when the keys are disjoint, which is why adding a
      # fresh subvolume (the datacore fixture's "@srv-data") is byte-for-byte
      # unchanged by this.
      subvolumes = recursiveUpdate baseSubvolumes extraSubvolumes;
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

# "0" is the no-swap sentinel and the ONLY spelling of it this function
  # understands; anything else must be a positive number of M or G. "0G" is the case
  # this exists for: it passed the installer's old `^(0|[0-9]+[MG])$`, then took the
  # swap branch — the sentinel comparison is against the exact string "0" — and
  # emitted a zero-length partition, found after destroy.
assert swapSize == "0"
  || builtins.match "[1-9][0-9]*[MG]" swapSize != null
  || throw ''mkDisk: swapSize must be "0" (no swap) or a positive size such as "8G" or "512M"; got "${toString swapSize}".'';

# btrfs or ext4, nothing else. Without this, "brtfs", "xfs" and "BTRFS" all fall
# through the `if` below into the ext4 branch and quietly produce an ext4 root on a
# machine whose owner asked for btrfs.
assert builtins.elem filesystem [ "btrfs" "ext4" ]
  || throw ''mkDisk: filesystem must be "btrfs" or "ext4"; got "${toString filesystem}".'';

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
