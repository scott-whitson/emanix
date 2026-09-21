{ config, lib, ... }:

let
  zellijDir = "${config.emanix.src.path}/zellij";

  # zellij's KDL parser performs NO expansion. Verified against 0.44.3:
  # "$HOME/x", "~/x" and a relative "x" are all taken literally, and a
  # theme_dir that does not resolve is a hard IoError — zellij refuses to
  # start at all. The KDL files therefore carry $HOME as a build-time
  # PLACEHOLDER, substituted here for the real home directory.
  #
  # Shell scripts under plugins/ are deliberately NOT substituted: $HOME
  # expands correctly there, and baking a path in would only make them
  # user-specific.
  substHome = builtins.replaceStrings [ "$HOME" ] [ config.home.homeDirectory ];
  renderKdl = f: substHome (builtins.readFile f);
in
{
  # Default false, and it stays that way on any host where Emacs IS the
  # desktop: EWM already gives persistence, tabs and splits, so a multiplexer
  # there is a second window manager inside the first. It is enabled on the
  # two hosts that are NOT an Emacs desktop and have a real use for it --
  # whistle (WSL, where zellij is how the box gets a usable terminal) and
  # datacore (headless, so a remote session survives a reboot). Consumers set
  # it per host; there is no role to inherit it from (roles were deleted
  # 2026-08-30).
  options.emanix.zellij.enable = lib.mkEnableOption
    "zellij with the zellaude bar, deployed live from zellij";

  config = lib.mkIf config.emanix.zellij.enable {
    # Package only — no `settings`: the kdl files in
    # zellij are the single source of truth, and
    # zellaude writes to its own settings json (a store copy would be
    # read-only). enableZshIntegration stays off; it would auto-start
    # zellij in every interactive shell.
    programs.zellij.enable = true;

    # SPLIT deployment, not one live symlink for the whole dir. The KDL files
    # need $HOME substituted (see renderKdl above), which can only happen at
    # build time, so they are generated; plugins/ stays a live out-of-store
    # symlink, preserving the property that HM recreates it every rebuild so a
    # plugin upgrade can't strand a stale hand-made link.
    #
    # Cost of the split: editing config.kdl or a layout now needs a rebuild to
    # take effect. That is the price of zellij not expanding anything — before
    # this, the KDL carried a hardcoded /home/<user> path instead, which worked
    # only for the one user who wrote it.
    xdg.configFile = {
      "zellij/config.kdl".text = renderKdl ../zellij/config.kdl;
      "zellij/layouts/default.kdl".text =
        renderKdl ../zellij/layouts/default.kdl;
      "zellij/plugins".source =
        config.lib.file.mkOutOfStoreSymlink "${zellijDir}/plugins";
    };

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
    # dirty the working tree — the Helix drift caveat at
    # https://emanix.net/docs/theming.html
    #
    # Colours are ANSI indices 0-15, so they resolve against whatever terminal
    # renders the session. Under ssh between hosts the rendering
    # terminal is the local ghostty, so hardcoded per-host colours would clash.
    # A palette switch therefore needs no zellij change at all; only dark/light
    # does.
    #
    # PER-DECLARATION format, not the bare fg/bg/black/white palette format.
    # The bare format cannot set theme_hue, which defaults to Dark, and
    # From<Palette> for Styling then derives background from palette.black —
    # so a light theme renders unselected rows on black. See data.rs and
    # kdl/mod.rs in zellij's source. Both definitions below are modelled on
    # zellij's own assets/themes/ansi.kdl; the light one exchanges the
    # greyscale ends (0<->15, 7<->8).
    #
    # BOTH are named `emanix`: zellij selects a theme by NAME, so switching
    # swaps which file is visible in theme_dir rather than editing config.kdl.
    home = {
      file = {
        ".local/share/emanix/zellij-themes/available/emanix-dark.kdl".text = ''
          themes {
            emanix {
              text_unselected {
                base 15
                background 0
                emphasis_0 9
                emphasis_1 6
                emphasis_2 2
                emphasis_3 5
              }
              text_selected {
                base 15
                background 8
                emphasis_0 9
                emphasis_1 6
                emphasis_2 2
                emphasis_3 5
              }
              ribbon_unselected {
                base 0
                background 7
                emphasis_0 1
                emphasis_1 15
                emphasis_2 4
                emphasis_3 5
              }
              ribbon_selected {
                base 0
                background 2
                emphasis_0 1
                emphasis_1 9
                emphasis_2 5
                emphasis_3 4
              }
              table_title {
                base 2
                background 0
                emphasis_0 9
                emphasis_1 6
                emphasis_2 2
                emphasis_3 5
              }
              table_cell_unselected {
                base 15
                background 0
                emphasis_0 9
                emphasis_1 6
                emphasis_2 2
                emphasis_3 5
              }
              table_cell_selected {
                base 15
                background 8
                emphasis_0 9
                emphasis_1 6
                emphasis_2 2
                emphasis_3 5
              }
              list_unselected {
                base 15
                background 0
                emphasis_0 9
                emphasis_1 6
                emphasis_2 2
                emphasis_3 5
              }
              list_selected {
                base 15
                background 8
                emphasis_0 9
                emphasis_1 6
                emphasis_2 2
                emphasis_3 5
              }
              frame_selected {
                base 2
                background 0
                emphasis_0 9
                emphasis_1 6
                emphasis_2 5
                emphasis_3 0
              }
              frame_highlight {
                base 9
                background 0
                emphasis_0 5
                emphasis_1 9
                emphasis_2 9
                emphasis_3 9
              }
              exit_code_success {
                base 2
                background 0
                emphasis_0 6
                emphasis_1 0
                emphasis_2 5
                emphasis_3 4
              }
              exit_code_error {
                base 1
                background 0
                emphasis_0 3
                emphasis_1 0
                emphasis_2 0
                emphasis_3 0
              }
              multiplayer_user_colors {
                player_1 5
                player_2 4
                player_3 0
                player_4 3
                player_5 6
                player_6 0
                player_7 1
                player_8 0
                player_9 0
                player_10 0
              }
            }
          }
        '';

        ".local/share/emanix/zellij-themes/available/emanix-light.kdl".text = ''
          themes {
            emanix {
              text_unselected {
                base 0
                background 15
                emphasis_0 9
                emphasis_1 6
                emphasis_2 2
                emphasis_3 5
              }
              text_selected {
                base 0
                background 7
                emphasis_0 9
                emphasis_1 6
                emphasis_2 2
                emphasis_3 5
              }
              ribbon_unselected {
                base 15
                background 8
                emphasis_0 1
                emphasis_1 0
                emphasis_2 4
                emphasis_3 5
              }
              ribbon_selected {
                base 15
                background 2
                emphasis_0 1
                emphasis_1 9
                emphasis_2 5
                emphasis_3 4
              }
              table_title {
                base 2
                background 15
                emphasis_0 9
                emphasis_1 6
                emphasis_2 2
                emphasis_3 5
              }
              table_cell_unselected {
                base 0
                background 15
                emphasis_0 9
                emphasis_1 6
                emphasis_2 2
                emphasis_3 5
              }
              table_cell_selected {
                base 0
                background 7
                emphasis_0 9
                emphasis_1 6
                emphasis_2 2
                emphasis_3 5
              }
              list_unselected {
                base 0
                background 15
                emphasis_0 9
                emphasis_1 6
                emphasis_2 2
                emphasis_3 5
              }
              list_selected {
                base 0
                background 7
                emphasis_0 9
                emphasis_1 6
                emphasis_2 2
                emphasis_3 5
              }
              frame_selected {
                base 2
                background 15
                emphasis_0 9
                emphasis_1 6
                emphasis_2 5
                emphasis_3 15
              }
              frame_highlight {
                base 9
                background 15
                emphasis_0 5
                emphasis_1 9
                emphasis_2 9
                emphasis_3 9
              }
              exit_code_success {
                base 2
                background 15
                emphasis_0 6
                emphasis_1 15
                emphasis_2 5
                emphasis_3 4
              }
              exit_code_error {
                base 1
                background 15
                emphasis_0 3
                emphasis_1 15
                emphasis_2 15
                emphasis_3 15
              }
              multiplayer_user_colors {
                player_1 5
                player_2 4
                player_3 15
                player_4 3
                player_5 6
                player_6 15
                player_7 1
                player_8 15
                player_9 15
                player_10 15
              }
            }
          }
        '';

      };

      # KEPT, where ghostty's equivalent was deleted on 2026-09-11. The
      # reasoning that retired seedGhosttyTheme -- `emanix/theme-init'
      # converges every target on first start, and the switch links zellij's
      # active theme too -- does not close this case, for two reasons that
      # compound:
      #
      # 1. theme-init converges only when ~/.config/dotfiles/active-theme is
      #    ABSENT or names a dead theme. Turning `emanix.zellij.enable' on for
      #    the first time on a host that already has a theme is therefore a
      #    rebuild after which the switch never runs, and nothing creates
      #    theme_dir. A fresh install is the only case the converge covers,
      #    and it is not the only case that produces a missing theme_dir.
      # 2. The failure is not cosmetic. A theme_dir that does not resolve is a
      #    hard IoError (verified against 0.44.3, see renderKdl above) and
      #    zellij refuses to start at all -- where ghostty's missing theme.conf
      #    only costs colours and still gives you a terminal. The cost of
      #    being wrong is asymmetric, and the hook is four lines.
      #
      # The `-e' guard means it can never fight the switcher: once Emacs has
      # written the symlink, every later activation is a no-op.
      activation.seedZellijTheme =
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          active="$HOME/.local/share/emanix/zellij-themes/active"
          run mkdir -p "$active"
          if [ ! -e "$active/theme.kdl" ]; then
            run ln -sfn \
              "$HOME/.local/share/emanix/zellij-themes/available/emanix-dark.kdl" \
              "$active/theme.kdl"
          fi
        '';
    };
  };
}
