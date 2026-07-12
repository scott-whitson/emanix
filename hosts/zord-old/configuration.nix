{ config, lib, pkgs, inputs, ... }:

{
  # zord-old — HP 15-ef2013dx (Ryzen 5 5500U, 32 GB)
  # This machine serves as the NixOS pilot before the T14 arrives.
  # After the T14 takes over as "zord", this becomes the backup/spare.
  #
  # Home Manager is imported from flake.nix via home-manager.nixosModules.

  networking.hostName = "zord-old";

  imports = [
    ../../modules/nixos/hardware/hp-15-ef2013dx.nix
    ../../modules/nixos/ewm.nix
    ../../modules/nixos/desktop.nix
  ];

  # Zsh — must be enabled at NixOS level so the shell is in PATH.
  programs.zsh.enable = true;

  # Auto-login on the console: the LUKS passphrase already gates the machine,
  # and the EWM launch hook (modules/nixos/ewm.nix) takes over tty1.
  services.getty.autologinUser = "scott";

  # User
  users.users.scott = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" "video" ];
    shell = pkgs.zsh;
  };

  # Locale
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # This value determines the NixOS release the config is compatible with.
  system.stateVersion = "24.11";
}