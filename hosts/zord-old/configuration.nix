{ ... }:

{
  # zord-old — HP 15-ef2013dx, backup/spare running the eminix stack.
  # Platform (os + i + shared net) comes from profiles/eminix.nix; hardware
  # from mkHost (ioshi/hi-hardware/hp-15-ef2013dx.nix); hostName from mkHost.
  # Nothing host-unique remains — autologin/tailscale/ssh/syncthing are now
  # shared in the eminix profile.
}
