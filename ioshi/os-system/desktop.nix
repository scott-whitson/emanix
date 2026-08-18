{ pkgs, ... }:

{
  # Shared NixOS desktop module (Phase 2).
  # Home Manager is imported from flake.nix via home-manager.nixosModules.

  # System packages (docker CLI comes from virtualisation.docker.enable)
  environment.systemPackages = with pkgs; [
    docker-compose
    love
  ];

  # nixpkgs.config (allowUnfree, permittedInsecurePackages) is set once in
  # flake.nix's nixpkgsModule so it applies to the whole system + HM.

  # Steam
  programs.steam.enable = true;


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
