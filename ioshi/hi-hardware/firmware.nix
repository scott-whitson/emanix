# Redistributable firmware, on by default.
#
# Without it, wifi does not come up on a large fraction of real laptops — the
# author's own two included, where nixos-hardware notably does NOT set it
# (verified: dropping it left the option false). A distribution whose installer
# completes and then cannot reach a network has not installed anything.
#
# Debian settled this same question the same way when it moved non-free
# firmware into the default installer media.
#
# mkDefault, not a plain definition: this is the distribution's opinion, and a
# host that would rather ship only free firmware overrides it without needing
# mkForce.
{ lib, ... }:

{
  hardware.enableRedistributableFirmware = lib.mkDefault true;
}
