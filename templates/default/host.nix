# The other machine-specific fact, alongside `username` in flake.nix (sed'd
# in by fresh-emanix-install during an interactive install, since mkHost
# takes it as a top-level argument rather than a value read out of a host
# module). Everything else in the template is static and reads from here.
# Edit it by hand and rebuild.
{
  hostName = "emanix";
  device = "/dev/vda";
  luks = false;
  filesystem = "btrfs";
  swapSize = "0";

  # Graphics driver to force-load in the initrd. The installer asks and sets
  # this; null is correct for a headless or virtualised host. A graphical host
  # with the wrong value here boots to a black screen, because a compositor
  # started from tty1 loses the DRM-master race — see emanix's
  # ioshi/hi-hardware/gpu.nix.
  gpu = null;

  # OPTIONAL. The name of a nixos-hardware module for this exact machine, e.g.
  # "lenovo-thinkpad-t14-amd-gen5". Leave null unless you know yours: emanix
  # does not guess, because nixos-hardware's names are not a convention and
  # guessing wrong before a disk is wiped is worse than not guessing. Browse
  # https://github.com/NixOS/nixos-hardware for the list.
  hardwareModule = null;
}
