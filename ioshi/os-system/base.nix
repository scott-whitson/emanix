{ config, lib, pkgs, ... }:

{
  # os layer — settings shared by every emanix host.
  programs.zsh.enable = true;

  # Docker on every role, base.nix included, because base.nix already puts the
  # primary user in the `docker` group unconditionally. It used to be declared
  # identically in os-system/{server,desktop}.nix and NOT in the wsl role, so a
  # WSL host carried a group grant for a daemon it did not have. Bootloader and
  # networkmanager stay in the desktop/server modules: WSL must not set a
  # bootloader, and NixOS-WSL manages its own networking.
  virtualisation.docker.enable = lib.mkDefault true;

  users.users.${config.emanix.username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" "video" ];
    shell = pkgs.zsh;
  };

  # Locale, time and keymap: NEUTRAL defaults, and all three mkDefault.
  #
  # timeZone was "America/New_York" as a bare definition until 2026-08-30. A
  # distribution deciding where its users live is the same class of thing as
  # deciding their password manager — and being a bare definition rather than
  # mkDefault, a consumer who disagreed got "conflicting definition values"
  # rather than an override. UTC is the honest default: correct for a server
  # anywhere, and wrong in a way that is immediately obvious to anyone who
  # cares, rather than silently right for one person.
  #
  # locale and keymap keep their conventional values — unlike a timezone there
  # IS a sensible default, and en_US.UTF-8 / us is it for this distro's author
  # base. They are mkDefault now too, so disagreeing costs one line and not an
  # mkForce.
  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  console.keyMap = lib.mkDefault "us";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;

    # Emergency valve. When a build drives free space below min-free, nix
    # collects garbage mid-build until max-free is available again. The weekly
    # timer alone is not enough on a churning host: a WSL host piled up 15.3 GiB of
    # dead paths in the 36 hours after its 2026-08-10 GC run.
    min-free = 5368709120; #  5 GiB
    max-free = 21474836480; # 20 GiB
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
