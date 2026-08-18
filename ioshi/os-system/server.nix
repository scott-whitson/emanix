{ ... }:

{
  # Shared NixOS server module.
  # NOT the whole i-intelligence dir: that default.nix is the Home Manager
  # aggregate (pi.nix/emacs.nix use `home.*`, an HM-only option) — importing
  # it at system level throws "definitions for `home', which is an option
  # that does not exist". Secrets (agenix) are supplied by the consuming
  # flake via extraModules, not by the distribution.

  # Headless server
  systemd.targets.multi-user.enable = true;

  # Network
  networking.networkmanager.enable = true;

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
