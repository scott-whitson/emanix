{ ... }:

{
  # eminix (T14) host-specific config.
  # Platform (os + i) comes from profiles/eminix.nix; hardware + disko layout
  # are wired in flake.nix via lib/mkHost.

  imports = [
    ../../ioshi/os-system/ni-options-doc.nix
  ];

  # Fresh install (2026) — pin the current release.
  system.stateVersion = "26.11";

  # Passwordless nixos-rebuild for scott: ni's rebuilds run from non-interactive
  # SSH sessions (no TTY for a sudo prompt). Scoped tightly to the rebuild
  # binary only — not blanket wheel NOPASSWD.
  security.sudo.extraRules = [{
    users = [ "scott" ];
    commands = [{
      command = "/run/current-system/sw/bin/nixos-rebuild";
      options = [ "NOPASSWD" ];
    }];
  }];
}
