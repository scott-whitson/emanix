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

    # gpu.nix and firmware.nix are COUPLED, and nothing else says so.
    #
    # Forcing amdgpu (or i915) into the initrd only helps if the driver's
    # firmware blobs are in the initrd with it, and the thing that puts them
    # there is `hardware.firmware`, which
    # hardware.enableRedistributableFirmware populates. firmware.nix's comment
    # explicitly invites a host to set that option false — a host that takes
    # the invitation while keeping a gpu value gets the exact black screen this
    # module exists to prevent.
    #
    # It has to be an assertion because the build will not complain otherwise:
    # boot.initrd.allowMissingModules defaults to TRUE, so a driver whose
    # firmware is absent is a line in a build log, not an error. The machine
    # builds, boots, probes, fails, and shows nothing.
    assertions = [{
      assertion = config.hardware.enableRedistributableFirmware;
      message = ''
        emanix.hardware.gpu is set to "${cfg.gpu}", which forces
        ${moduleFor.${cfg.gpu}} into the initrd, but
        hardware.enableRedistributableFirmware is false — so the driver's
        firmware blobs are not there and the probe will fail to a black
        screen (boot.initrd.allowMissingModules hides this at build time).

        Either leave hardware.enableRedistributableFirmware at emanix's
        default of true (see ioshi/hi-hardware/firmware.nix), or set
        emanix.hardware.gpu = null if this host has no display to bring up.
      '';
    }];
  };
}
