{ ... }:

{
  # eminix (T14) host-specific config.
  # Platform (os + i) comes from profiles/eminix.nix; hardware + disko layout
  # are wired in flake.nix via lib/mkHost.

  # Fresh install (2026) — pin the current release.
  system.stateVersion = "26.11";
}
