{ config, lib, ... }:

{
  options.scott.zellij.enable = lib.mkEnableOption
    "zellij with the zellaude bar, deployed live from ioshi/i-intelligence/zellij";

  config = lib.mkIf config.scott.zellij.enable {
    # Package only — no `settings`: the kdl files in
    # ioshi/i-intelligence/zellij are the single source of truth, and
    # zellaude writes to its own settings json (a store copy would be
    # read-only). enableZshIntegration stays off; it would auto-start
    # zellij in every interactive shell.
    programs.zellij.enable = true;

    # One live symlink for the whole config dir (same pattern as the
    # emacs lisp dir). HM recreates it every rebuild, so plugin upgrades
    # can't strand a stale hand-made link.
    xdg.configFile."zellij".source = config.lib.file.mkOutOfStoreSymlink
      "${config.scott.dotfiles.path}/ioshi/i-intelligence/zellij";

    # SSH logins land in the persistent session. Guards: never inside an
    # existing zellij, never for TRAMP (TERM=dumb). Not `exec`: detaching
    # should drop to a plain shell, not close the connection.
    programs.zsh.initContent = lib.mkAfter ''
      if [[ -n "$SSH_CONNECTION" && -z "$ZELLIJ" && "$TERM" != "dumb" ]]; then
        zellij attach --create main
      fi
    '';

    # Themes live OUTSIDE the checkout. ~/.config/zellij is an out-of-store
    # symlink into the repo, so a theme file written there at switch time would
    # dirty the working tree — the Helix drift caveat in docs/manual/02-theming.md.
    #
    # Colours are ANSI indices 0-15, not hex, on purpose: they resolve against
    # whatever terminal renders the session. Under ssh from rafik into whistle
    # the rendering terminal is rafik's ghostty, so hardcoded per-host colours
    # would clash. This also means a palette switch needs no zellij change at
    # all — only the dark/light role assignment differs below.
    #
    # BOTH themes are named `eminix`, deliberately. zellij selects a theme by
    # name, so switching is done by changing WHICH FILE is visible in theme_dir,
    # not by editing the `theme` line in config.kdl (which lives in the repo and
    # must stay clean). available/ is not theme_dir; active/ is.
    home.file.".local/share/dotfiles/zellij-themes/available/eminix-dark.kdl".text = ''
      themes {
          eminix {
              fg 7
              bg 0
              black 0
              red 1
              green 2
              yellow 3
              blue 4
              magenta 5
              cyan 6
              white 15
              orange 3
          }
      }
    '';

    home.file.".local/share/dotfiles/zellij-themes/available/eminix-light.kdl".text = ''
      themes {
          eminix {
              fg 0
              bg 15
              black 0
              red 1
              green 2
              yellow 3
              blue 4
              magenta 5
              cyan 6
              white 7
              orange 3
          }
      }
    '';

    # theme_dir must EXIST before zellij starts: pointing it at a missing
    # directory is a hard IoError, not a warning, and zellij refuses to run.
    # Seed the active symlink if absent, same pattern as ghostty's theme.conf.
    home.activation.seedZellijTheme =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        active="$HOME/.local/share/dotfiles/zellij-themes/active"
        run mkdir -p "$active"
        if [ ! -e "$active/theme.kdl" ]; then
          run ln -sfn \
            "$HOME/.local/share/dotfiles/zellij-themes/available/eminix-dark.kdl" \
            "$active/theme.kdl"
        fi
      '';
  };
}
