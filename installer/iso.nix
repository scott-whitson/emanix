# installer/iso.nix — the eminix installer ISO.
# A minimal NixOS live system (NOT an eminix host — never through mkHost) that
# carries the eminix distribution flake so a bare-metal install is:
# boot -> one command.
#
# The distribution is generic: it carries no user keys or secrets. Personal
# keys/secrets are supplied by the consuming flake (dotfiles) when building a
# customized ISO.
{ pkgs, lib, nixpkgs, disko, ... }:

let
  # The distro repo, staged without history/symlink so /etc/eminix/flake is a
  # clean, buildable flake tree.
  stagedRepo = builtins.path {
    name = "eminix-flake";
    path = ../.;
    filter = p: t:
      let b = builtins.baseNameOf p;
      in b != ".git" && b != "result" && b != "keys" && b != ".superpowers";
  };

  # True only when the builder staged keys/ (gitignored privates + committed pubs).
  hasKeys = builtins.pathExists ../keys;

  # disko from the flake input when exposed, else nixpkgs' package — either
  # way the installer does not `nix run` it over the network.
  diskoPkg = disko.packages.${pkgs.system}.default or pkgs.disko;
in
{
  imports = [ "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix" ];

  isoImage.volumeID = "eminix"; # boot menu + mount label

  # The flake (+ optional keys) at fixed, /mnt-safe paths. /etc lives on the
  # live overlay, so the disko step — which mounts the target root at /mnt —
  # cannot hide it (the trap that broke USB-staged repos mounted under /mnt).
  environment.etc =
    { "eminix/flake".source = stagedRepo; }
    // lib.optionalAttrs hasKeys { "eminix/keys".source = ../keys; }
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
}
