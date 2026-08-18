# Stub "hardware" for the flake's eval checks — NOT a real machine.
#
# NixOS asserts a root filesystem and a boot loader before it will produce a
# toplevel, and the checks force exactly that toplevel to make the module set
# evaluate. These three settings are the minimum that satisfies those
# assertions; nothing here is ever built or booted (see the checks output in
# flake.nix, which discards the derivation's string context).
{ ... }:
{
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  # Off rather than a device: the roles already enable systemd-boot, and a
  # grub device would only add a second, contradictory loader.
  boot.loader.grub.enable = false;

  # Per-host in a real deployment (see ioshi/os-system/base.nix); pinned here
  # only so the assertion is satisfied.
  system.stateVersion = "26.05";
}
