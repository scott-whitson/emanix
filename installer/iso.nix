# installer/iso.nix — the eminix installer ISO.
# A minimal NixOS live system (NOT an eminix host — never through mkHost) that
# carries the flake + host keys so a bare-metal install is: boot -> one command.
# Spec: docs/superpowers/specs/2026-08-15-eminix-installer-iso-design.md
{ pkgs, lib, nixpkgs, disko, ... }:

let
  # The repo, staged without history/symlink/keys so /etc/eminix/dotfiles is a
  # clean, buildable flake tree. builtins.path (not cleanSource) so the filter
  # is explicit. secrets/rekeyed/ is intentionally INCLUDED once Part II lands:
  # nixos-install builds from this tree, and agenix activates from it.
  stagedRepo = builtins.path {
    name = "eminix-dotfiles";
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

  # The flake + keys at fixed, /mnt-safe paths. /etc lives on the live overlay,
  # so the disko step — which mounts the target root at /mnt — cannot hide it
  # (the trap that broke USB-staged repos mounted under /mnt in 2026-08).
  environment.etc =
    { "eminix/dotfiles".source = stagedRepo; }
    // lib.optionalAttrs hasKeys { "eminix/keys".source = ../keys; }
    // {
      # The three commands, printed on every console login (and the ssh hint).
      "issue".text = ''
        ══ eminix installer ════════════════════════════════════════════
          repo : /etc/eminix/dotfiles
          keys : /etc/eminix/keys
          install a host:   sudo fresh-eminix-install <host> [--disk /dev/X]
          check only:       sudo fresh-eminix-install <host> --check-only
          remote access:    boot with live.nixos.passwd=<pw> on the kernel
                            cmdline, then ssh nixos@<ip> from rafik
        ═════════════════════════════════════════════════════════════════
      '';
    };

  environment.systemPackages = with pkgs; [
    # git is already enabled by installation-cd-base (programs.git) — nothing
    # to add for it.
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

  # sshd for driving the target from rafik. Host keys are generated fresh at
  # every boot (live tmpfs) — ephemeral by construction. The nixos user has an
  # EMPTY password on the ISO, so with PermitEmptyPasswords no (sshd default)
  # nothing can log in remotely until a password is set — which the ISO
  # already supports via the `live.nixos.passwd=<pw>` kernel cmdline
  # (installation-cd-base's postBootCommands) or `sudo passwd nixos` at the
  # console. Anyone holding the stick can boot it and read /etc/eminix/keys as
  # root via passwordless sudo regardless, so ssh adds no exposure.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  # The installer runs `nixos-install --flake`, `nix run`, disko etc.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
