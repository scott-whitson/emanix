_:

{
  # Shared NixOS desktop module (Phase 2).
  # Home Manager is imported from flake.nix via home-manager.nixosModules.
  #
  # nixpkgs.config (allowUnfree, permittedInsecurePackages) is set once in
  # flake.nix's nixpkgsModule so it applies to the whole system + HM.
  #
  # There is deliberately NO environment.systemPackages and NO programs.steam
  # here. What this module contributes is HARDWARE and SERVICES a desktop needs
  # — audio, bluetooth, printing, touchpad — not a set of applications. The
  # three that used to live here all left in 2026-08-30:
  #
  #   programs.steam  gaming; moved to dotfiles with its Xwayland wrapper, which
  #                   execs the binary this option provides — the two halves had
  #                   to move together.
  #   love            a 2D GAME ENGINE, same class as steam. Moved to dotfiles.
  #   docker-compose  VESTIGIAL, deleted rather than moved. Nothing invokes the
  #                   hyphenated form: datacore's eight stack scripts all use
  #                   `docker compose`, the v2 plugin that comes with docker
  #                   itself (virtualisation.docker.enable, set for every eminix
  #                   box in os-system/base.nix). Only a README still names the
  #                   old binary.
  #
  # `_:` and not `{ pkgs, ... }:` because nothing here needs pkgs any more, and
  # deadnix is part of this repo's own lint gate.

  # Network
  networking.networkmanager.enable = true;

  # Bluetooth
  hardware.bluetooth.enable = true;

  # Audio
  security.rtkit.enable = true;

  # Printing, input (touchpad), and audio (pipewire)
  services = {
    printing.enable = true;

    # Input — touchpad (user preference, shared across hosts)
    libinput = {
      enable = true;
      touchpad = {
        naturalScrolling = true;
        disableWhileTyping = true;
      };
    };

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };
  };

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
