# Redistributable firmware, on by default.
#
# Without it, wifi does not come up on a large fraction of real laptops — the
# author's own two included. On those two machines the nixos-hardware module in
# use does not set it either (verified: dropping this line left the option
# false), so importing a per-model module is not a substitute. That is a
# measurement of those machines, not a general claim about upstream — a dozen
# or so nixos-hardware modules DO set it. A distribution whose installer
# completes and then cannot reach a network has not installed anything.
#
# Debian settled this same question the same way when it moved non-free
# firmware into the default installer media.
#
# mkDefault, not a plain definition: this is the distribution's opinion, and a
# host that would rather ship only free firmware overrides it without needing
# mkForce.
#
# But see the assertion in gpu.nix before you take that up: setting this false
# while emanix.hardware.gpu is non-null removes the firmware the forced initrd
# driver needs, and boot.initrd.allowMissingModules makes that a build-log
# warning rather than an error. The assertion turns it into a build failure
# naming both options.
#
# The cost of the default is roughly 791 MiB of closure (linux-firmware), paid
# by EVERY emanix host including headless and WSL ones — see the note above
# this module's import in emanix.nix.
{ lib, ... }:

{
  hardware.enableRedistributableFirmware = lib.mkDefault true;
}
