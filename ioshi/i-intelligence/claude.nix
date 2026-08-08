{ config, ... }:

{
  # Claude Code settings. NOT a store file: Claude Code writes this at runtime
  # (model changes, plugin toggles, hook edits), so a read-only /nix/store copy
  # would break it. Same live-symlink pattern as zellij.nix and the emacs lisp
  # dir — edits take effect immediately, no rebuild.
  #
  # Known trade-off, chosen deliberately 2026-08-07: because the target is
  # inside the checkout, Claude Code's runtime writes show up as a dirty
  # working tree. That is the price of keeping these settings version-
  # controlled and synced across hosts.
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.scott.dotfiles.path}/ioshi/i-intelligence/claude/settings.json";
}
