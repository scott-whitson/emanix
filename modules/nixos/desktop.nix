{ config, lib, pkgs, ... }:

{
  # Shared NixOS desktop module (Phase 2).
  # Home Manager is imported from flake.nix via home-manager.nixosModules.

  # System packages (docker CLI comes from virtualisation.docker.enable)
  environment.systemPackages = with pkgs; [
    docker-compose
  ];

  # nixpkgs.config (allowUnfree, permittedInsecurePackages) is set once in
  # flake.nix's nixpkgsModule so it applies to the whole system + HM.

  # Steam
  programs.steam.enable = true;


  # Docker
  virtualisation.docker.enable = true;

  # Network
  networking.networkmanager.enable = true;

  # Printing
  services.printing.enable = true;

  # Bluetooth
  hardware.bluetooth.enable = true;

  # Input — touchpad (user preference, shared across hosts)
  services.libinput = {
    enable = true;
    touchpad = {
      naturalScrolling = true;
      disableWhileTyping = true;
    };
  };

  # Audio
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}