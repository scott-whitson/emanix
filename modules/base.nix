{ config, lib, pkgs, ... }:

{
  # os layer — settings shared by every emanix host.
  programs.zsh.enable = true;

  # Docker is on for every host, including WSL, because base.nix already puts
  # the primary user in the `docker` group unconditionally. It used to be
  # declared identically in the old desktop and server role modules and NOT in
  # the WSL role, so a WSL host carried a group grant for a daemon it did not
  # have. Neither the bootloader nor NetworkManager is set here: a bootloader
  # is a fact about a machine, and NixOS-WSL manages its own networking, so
  # both belong to the consuming flake (the template sets them).
  virtualisation.docker.enable = lib.mkDefault true;

  users.users.${config.emanix.username} = {
    isNormalUser = true;
    # mkDefault, and docker is NOT here: docker-group membership is equivalent
    # to root (`docker run -v /:/host`), so a distribution should not grant it
    # by default -- a consumer that wants it adds one line, and mkDefault is
    # what makes that line possible rather than a conflict. networkmanager is
    # conditional because the group only exists when the consumer enables
    # NetworkManager; on a host without it the grant was dangling.
    extraGroups = lib.mkDefault ([ "wheel" "video" ]
      ++ lib.optional config.networking.networkmanager.enable "networkmanager");
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
    # collects garbage mid-build until max-free is available again. The daily
    # timer alone is not enough on a churning host: a WSL host piled up 15.3 GiB of
    # dead paths in the 36 hours after its 2026-08-10 GC run.
    min-free = 5368709120; #  5 GiB
    max-free = 21474836480; # 20 GiB
  };

  # Daily GC keeps the store lean, with a rollback window wide enough to use.
  # It was 3d, which is not: a bad update, or a distribution regression you only
  # notice when you reach for the thing that broke, could not be rolled back by
  # the time you knew. Generations are the only safety net a NixOS user has, and
  # `nixos-rebuild switch --rollback` needs one that still exists. Two weeks
  # costs disk, not correctness.
  #
  # nix-collect-garbage takes --delete-older-than; --delete-generations is a
  # nix-env flag and is not accepted here.
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 14d";
  };

  # NOTE: system.stateVersion is per-host — it records the release a machine was
  # first installed under and must NOT be shared or bumped on an existing host.
  # Set it in the consumer's host config.
}
