{ ... }:

{
  # The eminix distribution — common core.
  # What is true of EVERY eminix box, regardless of shape. This is exactly the
  # set whistle had been importing by hand before it moved to mkHost.
  #
  # Deliberately NOT here:
  #   - net/syncthing.nix  : system-level syncthing suits workstation/server,
  #                          but whistle runs an HM-level one (profile "wsl").
  #   - desktop/ewm/ollama : workstation concerns, see roles/workstation.nix
  imports = [
    ../ioshi/os-system/base.nix
    ../ioshi/hi-hardware/net/tailscale.nix
    ../ioshi/hi-hardware/net/ssh.nix
    ../ioshi/i-intelligence/secrets.nix
  ];
}
