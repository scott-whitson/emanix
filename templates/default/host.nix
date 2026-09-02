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
}
