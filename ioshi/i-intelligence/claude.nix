{ config, lib, ... }:

{
  options.eminix.claude = {
    enable = lib.mkEnableOption ''
      the Claude Code settings symlink. Off by default: the distro does not
      install the Claude CLI, so deploying its settings on a host that never
      runs it is noise. Enable on the hosts that actually use it
    '';

    settingsSource = lib.mkOption {
      # str, NOT path. A path LITERAL is copied into the store at eval, so
      # mkOutOfStoreSymlink below would target a read-only /nix/store copy —
      # which is precisely what this module exists to avoid, since Claude Code
      # rewrites the file at runtime. Keeping it a string preserves the real
      # checkout path. Same reasoning as src.themesDir / src.binDir.
      type = lib.types.str;
      default = "${config.eminix.src.dotfilesPath}/claude/settings.json";
      example = "/home/alice/dotfiles/home/alice/claude/settings.json";
      description = ''
        Absolute path to the settings.json to live-symlink to
        ~/.claude/settings.json. Must live in the consumer's checkout: the
        distro ships no settings of its own, and the file has to stay
        writable.
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
    home.file.".claude/settings.json" = lib.mkIf config.eminix.claude.enable {
      source = config.lib.file.mkOutOfStoreSymlink
        (toString config.eminix.claude.settingsSource);
    };
  };
}
