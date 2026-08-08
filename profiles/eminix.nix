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
    ../ioshi/os-system/firstboot.nix
    ../ioshi/hi-hardware/net/tailscale.nix
    ../ioshi/hi-hardware/net/ssh.nix
    ../ioshi/i-intelligence/secrets.nix
    # IB Gateway is fully option-gated (scott.ibgateway.enable, default false),
    # so importing it here only makes the option available — it costs nothing on
    # hosts that leave it off. Kept in the core rather than a role because an
    # always-on headless box is at least as natural a home for it as a laptop.
    ../ioshi/i-intelligence/ibgateway.nix
  ];
}
