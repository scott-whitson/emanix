{ config, lib, pkgs, ... }:

{
  # os layer — settings shared by every eminix host.
  programs.zsh.enable = true;

  users.users.${config.eminix.username} = {
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

    # Emergency valve. When a build drives free space below min-free, nix
    # collects garbage mid-build until max-free is available again. The weekly
    # timer alone is not enough on a churning host: a WSL host piled up 15.3 GiB of
    # dead paths in the 36 hours after its 2026-08-10 GC run.
    min-free = 5368709120;   #  5 GiB
    max-free = 21474836480;  # 20 GiB
  };

  # Daily, not weekly. On a WSL host the vhdx never shrinks below its
  # high-water mark, so garbage that lives for six days costs real disk on the
  # Windows side even after it is collected.
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 14d";
  };

  # NOTE: system.stateVersion is per-host — it records the release a machine was
  # first installed under and must NOT be shared or bumped on an existing host.
  # Set it in each hosts/<name>/configuration.nix.
}
