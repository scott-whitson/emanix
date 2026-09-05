# What EWM needs from a GPU.
#
# EWM launches from tty1 autologin at boot and loses the DRM-master race
# against late GPU bring-up, so the driver must be in the INITRD, forced to
# load. This was verified on zord-old with amdgpu, and the same comment used to
# be written twice — once per machine — in a personal repo, which is what
# identified it as a fact about the compositor rather than about a ThinkPad.
#
# boot.initrd.kernelModules, not availableKernelModules: the latter only
# PERMITS a module in the initrd, and nixos-generate-config already writes it.
# Nothing generate-config produces forces the load, which is why this option
# cannot be derived from a generated hardware-configuration.nix.
#
# NixOS tier, not Home Manager: it drives boot.*, which HM cannot reach.
#
# amd:   verified (zord-old, and both AMD machines in the author's fleet).
# intel: REASONED, NOT VERIFIED. The DRM-master race is a property of starting
#        a compositor before userspace has settled, not a property of amdgpu,
#        and i915 is the equivalent module. Applying a verified mechanism to a
#        second driver is a different act from inventing a config, but it is
#        not a test. If you have an Intel machine and this is wrong, say so.
# nvidia: deliberately absent. Wayland plus the proprietary driver is a
#        project, not a line, and shipping a guess here would be a claim the
#        distribution cannot back.
{ config, lib, ... }:

let
  cfg = config.emanix.hardware;
  moduleFor = { amd = "amdgpu"; intel = "i915"; };
in
{
  options.emanix.hardware.gpu = lib.mkOption {
    type = lib.types.nullOr (lib.types.enum [ "amd" "intel" ]);
    default = null;
    example = "amd";
    description = ''
      Graphics driver to force-load in the initrd, so a compositor started
      from tty1 does not lose the DRM-master race. null contributes nothing,
      which is correct for a headless or virtualised host.
    '';
  };

  config = lib.mkIf (cfg.gpu != null) {
    boot.initrd.kernelModules = [ moduleFor.${cfg.gpu} ];
  };
}
