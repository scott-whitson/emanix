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
    #
    # `white` is NOT a free colour identity — a prior comment here claimed
    # black/white should be held constant across variants "like ANSI names."
    # That was wrong, disproven by zellij-utils 0.44.3's own source, not by a
    # live session:
    #
    #   - zellij-utils/src/kdl/mod.rs, Themes::from_kdl, "Older palette based
    #     theme definition" branch: this bare fg/bg/black/.../white format
    #     builds a `Palette { ..., ..Default::default() }`, and
    #     `ThemeHue::default() == Dark` (zellij-utils/src/data.rs). The bare
    #     format has NO KDL key for theme_hue, so it is Dark for every theme
    #     written this way — for BOTH our files, regardless of which one is
    #     meant to look "light."
    #   - zellij-utils/src/data.rs, `impl From<Palette> for Styling`: this is
    #     what actually turns our 11 fields into the ~13 StyleDeclarations
    #     zellij paints with. It opens with
    #       let (fg, bg) = match palette.theme_hue {
    #         Light => (palette.black, palette.white),
    #         Dark  => (palette.white, palette.black),
    #       };
    #     Since theme_hue is always Dark here, `white` becomes the `base`
    #     (foreground) of text_unselected/text_selected/table_cell_(un)selected/
    #     list_(un)selected, and `black` becomes background in several of the
    #     same. `white` is also used directly (not via the hue match) as
    #     ribbon_unselected/list_(un)selected's base/emphasis_1. It is a TEXT
    #     colour as consumed, exactly like fg/bg — not a fixed identity.
    #
    # Consequence: text_selected/table_cell_selected/list_selected pair
    # `base = white` against `background = palette.bg` (the raw bg field, not
    # hue-swapped). The old light `white 15` against `bg 15` was therefore the
    # identical PaletteColor value in all three — proven with a small script
    # modelling the From<Palette> impl (task-6-report.md, Fix round 2), not
    # guessed at rendering. `white 7` (before that) missed the exact
    # collision but is a light grey against a light bg — still low contrast.
    #
    # Chosen instead: `white 8` for the light theme. Modelling every base/
    # background pair the source derives (see the report) shows 8 is the
    # darkest neutral ANSI slot (conventionally "bright black" — a mid grey,
    # not a hue) that causes NO exact collision anywhere `white` feeds in,
    # for either variant. It cannot be optimal in both directions at once:
    # the same scalar is also `base` against `background = black` (0) in
    # text_unselected/table_cell_unselected/list_unselected, where a darker
    # value buys less contrast than 15 would have — an inherent limit of this
    # older bare-palette format (zellij's own bundled *-light.kdl themes, e.g.
    # ayu-light.kdl, avoid it entirely by using the newer per-declaration
    # format instead, where base/background are set explicitly with no hue
    # inference). Switching formats is a bigger change than this fix; flagged
    # for a future round rather than done here.
    #
    # Separately, and NOT fixed here: the same modelling shows
    # ribbon_unselected in the light file pairs `base = black` (0) against
    # `background = fg` (0) — an exact collision that has nothing to do with
    # `white` and predates this fix (light's fg has been 0 since Step 1).
    # Fixing it would mean moving `fg` (reviewed and confirmed correct
    # elsewhere) or `black` (meant to read as true black in both variants) —
    # out of scope for this round; see task-6-report.md.
    #
    # Dark's `white 15` against `bg 0`/`black 0` has no such collision (15
    # never equals 0) and is unchanged.
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
              white 8
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
