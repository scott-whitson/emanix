{ pkgs, ... }:

{
  # os layer — settings shared by every eminix host.
  programs.zsh.enable = true;

  users.users.scott = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" "video" ];
    shell = pkgs.zsh;
  };

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # NOTE: system.stateVersion is per-host — it records the release a machine was
  # first installed under and must NOT be shared or bumped on an existing host.
  # Set it in each hosts/<name>/configuration.nix.
}
