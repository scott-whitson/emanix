{ ... }:

{
  # The eminix platform (NixOS side): os + i composed.
  # Hosts add their hi layer (hardware + disko) via lib/mkHost.
  imports = [
    ../ioshi/os-system/base.nix
    ../ioshi/os-system/desktop.nix
    ../ioshi/i-intelligence/ewm.nix
  ];
}
