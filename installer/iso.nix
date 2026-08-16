# installer/iso.nix — the eminix installer ISO.
# A minimal NixOS live system (NOT an eminix host — never through mkHost) that
# carries a flake + optional host keys so a bare-metal install is:
# boot -> one command.
#
# The distribution is generic: it carries no user keys or secrets. By default
# it stages the eminix distro flake with NO keys (debug/rescue ISO). A
# consuming flake (e.g. the user's dotfiles, which holds the real hosts and
# keys) builds its own installer by importing this module and setting
#   eminix.installer.flake    = <path to their flake repo>
#   eminix.installer.keysDir  = <path to their keys dir>   (optional)
# and re-exporting the resulting `config.system.build.isoImage`.
{ pkgs, lib, nixpkgs, disko, config, ... }:

let
  cfg = config.eminix.installer;

  # The flake repo to stage, filtered so /etc/eminix/flake is a clean,
  # buildable tree (no history/symlink/result).
  stagedRepo = builtins.path {
    name = "eminix-flake";
    path = cfg.flake;
    filter = p: t:
      let b = builtins.baseNameOf p;
      in b != ".git" && b != "result" && b != "keys" && b != ".superpowers";
  };

  # Keys are only staged when the builder provides a keysDir (gitignored
  # privates + committed pubs).
  hasKeys = cfg.keysDir != null && builtins.pathExists cfg.keysDir;

  # disko from the flake input when exposed, else nixpkgs' package — either
  # way the installer does not `nix run` it over the network.
  diskoPkg = disko.packages.${pkgs.system}.default or pkgs.disko;
in
{
  imports = [ "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix" ];

  options.eminix.installer = {
    flake = lib.mkOption {
      type = lib.types.path;
      default = ../.;
      description = "Path to the flake repo the ISO stages at /etc/eminix/flake.";
    };
    keysDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a keys/ dir (host_ed25519 key pairs) to stage at /etc/eminix/keys. Null stages no keys.";
    };
  };

  config = {
    isoImage.volumeID = "eminix"; # boot menu + mount label

  # The flake (+ optional keys) at fixed, /mnt-safe paths. /etc lives on the
  # live overlay, so the disko step — which mounts the target root at /mnt —
  # cannot hide it (the trap that broke USB-staged repos mounted under /mnt).
  environment.etc =
    { "eminix/flake".source = stagedRepo; }
    // lib.optionalAttrs hasKeys { "eminix/keys".source = cfg.keysDir; }
    // {
      "issue".text = ''
        ══ eminix installer ════════════════════════════════════════════
          flake : /etc/eminix/flake
          keys  : /etc/eminix/keys (only when a customized ISO carried them)
          install a host:  sudo fresh-eminix-install <host> [--disk /dev/X]
          check only:      sudo fresh-eminix-install <host> --check-only
          remote access:   boot with live.nixos.passwd=<pw> on the kernel
                           cmdline, then ssh nixos@<ip>
        ═════════════════════════════════════════════════════════════════
      '';
    };

  environment.systemPackages = with pkgs; [
    exfatprogs # mounting arbitrary USB sticks
    dosfstools
    diskoPkg
    (pkgs.writeShellScriptBin "fresh-eminix-install" (builtins.readFile ./fresh-eminix-install))
    (pkgs.writeShellScriptBin "eminix-firstboot" (builtins.readFile ./eminix-firstboot))
  ];

  # WiFi — the installer profile (installation-device.nix) already enables
  # NetworkManager. Point its backend at iwd so BOTH nmcli/nmtui and the
  # runbook's iwctl work, and avoid the wpa_supplicant backend that iwd is
  # mutually exclusive with (nixpkgs enables iwd automatically for this
  # backend).
  networking.networkmanager.wifi.backend = "iwd";

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
