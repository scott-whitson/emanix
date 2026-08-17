{ config, lib, ... }:

{
  options.eminix.claude = {
    settingsSource = lib.mkOption {
      type = lib.types.path;
      default = ./claude/settings.json;
      description = ''
        Path to a claude settings.json to live-symlink to ~/.claude/settings.json.
        Defaults to the distro's generic file (model + theme only, no hooks).
        Consumers that want personal hooks/models point this at a file in their
        own checkout.
      '';
    };
  };

  config = {
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
        (toString config.eminix.claude.settingsSource);
  };
}
