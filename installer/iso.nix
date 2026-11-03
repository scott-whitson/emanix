# installer/iso.nix — the emanix installer ISO.
# A minimal NixOS live system (NOT an emanix host — never through mkHost) that
# carries the distro flake and NOTHING ELSE, so a bare-metal install is:
# boot -> one command.
#
# It is keyless BY CONSTRUCTION, and that is not a default that can be turned
# off. Every file in a NixOS image comes from /nix/store, which is world
# readable, so an image that "carries" a private key has published it; there is
# no way to bake key material into an ISO without it landing in the store. The
# target's host key is therefore minted on the target, and the fleet path reads
# its keys from a directory beside the repo at install time (a removable
# medium) — never from the image. docs/decisions/keys-never-in-the-store.md.
#
# A consuming flake (the user's dotfiles, which holds the real hosts) imports
# this module, sets emanix.installer.flake = <path to their flake repo>, and
# re-exports the resulting `config.system.build.isoImage`.
{ pkgs, lib, nixpkgs, disko, config, ... }:

let
  cfg = config.emanix.installer;

  # The flake repo to stage, filtered so /etc/emanix/flake is a clean,
  # buildable tree (no history/symlink/result).
  #
  # `keys` is NOT filtered out, and it holds only PUBLIC halves: the committed
  # `keys/<host>_host_ed25519.pub` is the reference resolve_keys verifies a
  # staged private half against, and a .pub in the store is not a secret — it is
  # the same string already in this repository. Private halves are gitignored in
  # the consuming flake, so a git-source `flake` path cannot carry them, and
  # nothing in this module stages a private key under any option.
  stagedRepo = builtins.path {
    name = "emanix-flake";
    path = cfg.flake;
    filter = p: _t:
      let b = builtins.baseNameOf p;
      in b != ".git" && b != "result" && b != ".superpowers";
  };

  # disko from the flake input when exposed, else nixpkgs' package — either
  # way the installer does not `nix run` it over the network.
  diskoPkg = disko.packages.${pkgs.system}.default or pkgs.disko;
in
{
  imports = [ "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix" ];

  options.emanix.installer = {
    flake = lib.mkOption {
      type = lib.types.path;
      default = ../.;
      description = "Path to the flake repo the ISO stages at /etc/emanix/flake.";
    };
  };

  config = {
    isoImage.volumeID = "emanix"; # boot menu + mount label

    # The flake at a fixed, /mnt-safe path. /etc lives on the live overlay, so the disko step — which mounts the target root at /mnt —
    # cannot hide it (the trap that broke USB-staged repos mounted under /mnt).
    environment.etc = {
      "emanix/flake".source = stagedRepo;
      "issue".text = ''
        ══ emanix installer ════════════════════════════════════════════
          flake : /etc/emanix/flake
          keys  : minted on the target, or read from <repo>-keys/ beside a
                  repo you staged yourself -- never from this image
          install a host:  sudo fresh-emanix-install <host> [--disk /dev/X]
            new machine:     sudo fresh-emanix-install        (asks, then installs)
            unattended:      EMANIX_USER_PASSWORD=... sudo -E fresh-emanix-install
                             (answers from stdin; LUKS must be answered 'n')
            check only:      sudo fresh-emanix-install <host> --check-only
            remote access:   set one at the console, then ssh nixos@<ip>
                             (sudo passwd nixos -- the kernel cmdline is
                             world-readable, so it is not offered here)
          ═════════════════════════════════════════════════════════════════
      '';
    };

    environment.systemPackages = with pkgs; [
      exfatprogs # mounting arbitrary USB sticks
      dosfstools
      diskoPkg
      (pkgs.writeShellScriptBin "fresh-emanix-install" (builtins.readFile ./fresh-emanix-install))
      # emanix-firstboot is deliberately NOT here. It runs on the INSTALLED
      # system after reboot, where modules/firstboot.nix puts it on PATH with
      # the consumer's content — running it inside the live ISO would act on the
      # installer environment, not the machine being built. Its body also left
      # the distribution entirely (it was one deployment's tailnet join), so
      # there is nothing generic left here to bake in.
    ];

    # WiFi — the installer profile (installation-device.nix) already enables
    # NetworkManager. Point its backend at iwd so BOTH nmcli/nmtui and the
    # runbook's iwctl work, and avoid the wpa_supplicant backend that iwd is
    # mutually exclusive with (nixpkgs enables iwd automatically for this
    # backend).
    networking.networkmanager.wifi.backend = "iwd";

    # Start NetworkManager only after iwd. Neither nixpkgs module orders the
    # pair, and on one bare-metal host (ath11k, 2026-09-28) the live ISO came up
    # with `wlan0` present but NM reporting it "unavailable" and
    # `iwctl station wlan0` saying "Device wlan0 not found". Stopping NM,
    # restarting iwd, then starting NM fixed it every time, which points at the
    # startup order. `wants` pulls iwd in; `after` makes NM wait for it.
    systemd.services.NetworkManager = {
      wants = [ "iwd.service" ];
      after = [ "iwd.service" ];
    };

    # sshd for driving the target remotely. Host keys are generated fresh at
    # every boot (live tmpfs) — ephemeral by construction. The nixos user has an
    # EMPTY password on the ISO, so nothing can log in remotely until a password
    # is set (via the `live.nixos.passwd=<pw>` kernel cmdline or `sudo passwd
    # nixos` at the console).
    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = true;
    };

    # The installer runs `nixos-install --flake`, `nix run`, disko etc.
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
  };
}
