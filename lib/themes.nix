{ pkgs, lib ? pkgs.lib, ... }:

rec {
  # Theme palette definitions and config generators.
  # Each theme is a palette + variant; each generator produces app config text.
  #
  # Usage from an HM module:
  #   lib.theme.generators.ghostty lib.theme.palettes.catppuccin-mocha
  #
  # Or from a host config:
  #   lib.theme.mkTheme "catppuccin-mocha" lib.theme.palettes.catppuccin-mocha

  palettes = {
    catppuccin-mocha = {
      variant = "dark";
      # The Emacs theme package this palette maps to. Not derivable from
      # colours — it names a package — so it belongs with the palette rather
      # than in a hand-written file beside the generated ones.
      emacsTheme = "catppuccin";
      colors = {
        rosewater = "#f5e0dc";
        flamingo = "#f2cdcd";
        pink = "#f5c2e7";
        mauve = "#cba6f7";
        red = "#f38ba8";
        maroon = "#eba0ac";
        peach = "#fab387";
        yellow = "#f9e2af";
        green = "#a6e3a1";
        teal = "#94e2d5";
        sky = "#89dceb";
        sapphire = "#74c7ec";
        blue = "#89b4fa";
        lavender = "#b4befe";
        text = "#cdd6f4";
        subtext1 = "#bac2de";
        subtext0 = "#a6adc8";
        overlay2 = "#9399b2";
        overlay1 = "#7f849c";
        overlay0 = "#6c7086";
        surface2 = "#585b70";
        surface1 = "#45475a";
        surface0 = "#313244";
        base = "#1e1e2e";
        mantle = "#181825";
        crust = "#11111b";
      };
    };

    catppuccin-latte = {
      variant = "light";
      emacsTheme = "catppuccin";
      colors = {
        rosewater = "#dc8a78";
        flamingo = "#dd7878";
        pink = "#ea76cb";
        mauve = "#8839ef";
        red = "#d20f39";
        maroon = "#e64553";
        peach = "#fe640b";
        yellow = "#df8e1d";
        green = "#40a02b";
        teal = "#179299";
        sky = "#04a5e5";
        sapphire = "#209fb5";
        blue = "#1e66f5";
        lavender = "#7287fd";
        text = "#4c4f69";
        subtext1 = "#5c5f77";
        subtext0 = "#6c6f85";
        overlay2 = "#7c7f93";
        overlay1 = "#8c8fa1";
        overlay0 = "#9ca0b0";
        surface2 = "#acb0be";
        surface1 = "#bcc0cc";
        surface0 = "#ccd0da";
        base = "#eff1f5";
        mantle = "#e6e9ef";
        crust = "#dce0e8";
      };
    };

    # High-contrast pair. Driven by an accessibility need (visual snow
    # syndrome), not aesthetics — see the 2026-08-09 spec. Deliberately NOT
    # 21:1: pure #fff on #000 causes halation, which is commonly worse than a
    # softened pair, and a pure-white background is a photophobia trigger.
    # Every accent below clears 7:1 against its own base; tests/contrast-check.py
    # enforces that. Do not "tidy" these values without re-running it.
    high-contrast-dark = {
      variant = "dark";
      emacsTheme = "modus-vivendi";
      colors = {
        rosewater = "#ffd7d0";
        flamingo = "#ffb3a7";
        pink = "#ff9ee0";
        mauve = "#c9a3ff";
        red = "#ff6b6b";
        maroon = "#ff8f8f";
        peach = "#ffb060";
        yellow = "#ffd93d";
        green = "#5ee06a";
        teal = "#4fe0c8";
        sky = "#5fd7ff";
        sapphire = "#4cc8f0";
        blue = "#7ab8ff";
        lavender = "#b9c4ff";
        text = "#e8e8e8";
        subtext1 = "#dcdcdc";
        subtext0 = "#cfcfcf";
        overlay2 = "#b2b2b2";
        overlay1 = "#9e9e9e";
        overlay0 = "#9b9b9b";
        surface2 = "#3d3d3d";
        surface1 = "#2e2e2e";
        surface0 = "#1f1f1f";
        base = "#0a0a0a";
        mantle = "#050505";
        crust = "#000000";
      };
    };

    high-contrast-light = {
      variant = "light";
      emacsTheme = "modus-operandi";
      colors = {
        rosewater = "#8a3324";
        flamingo = "#95291e";
        pink = "#9d006b";
        mauve = "#6b21a8";
        red = "#a70019";
        maroon = "#96001a";
        peach = "#804000";
        yellow = "#654d00";
        green = "#0d5e1b";
        teal = "#005a56";
        sky = "#005776";
        sapphire = "#00567a";
        blue = "#0043a8";
        lavender = "#3b3ba8";
        text = "#111111";
        subtext1 = "#212121";
        subtext0 = "#2e2e2e";
        overlay2 = "#3a3a3a";
        overlay1 = "#4a4a4a";
        overlay0 = "#515151";
        surface2 = "#b0b0b0";
        surface1 = "#c4c4c4";
        surface0 = "#d6d6d6";
        base = "#f2f2f2";
        mantle = "#e8e8e8";
        crust = "#dedede";
      };
    };
  };

  # ANSI slots 0-15, in order. Light palettes exchange the greyscale ends
  # (0<->15 and 7<->8): index 0 is "black" and 15 is "white", so on a light
  # palette they must be the DARK and LIGHT extremes respectively. The old
  # hardcoded order applied the dark mapping to every palette, which put a
  # light colour at index 0 on latte — inverted, and disagreeing with
  # themes/catppuccin-latte/colors.toml, which had it right.
  #
  # This is not cosmetic: zellij themes and Claude Code's -ansi themes read
  # these indices, so an inverted light palette renders unreadable.
  #
  # colorsToml below (this same file) consumes this ordering directly for
  # [ansi] — there is no separate generator that must be kept in sync.
  ansiSlots = palette:
    let accents = [ "red" "green" "yellow" "blue" "pink" "teal" ];
    in
    if palette.variant == "light"
    then [ "subtext1" ] ++ accents ++ [ "surface2" "subtext0" ] ++ accents ++ [ "surface1" ]
    else [ "surface1" ] ++ accents ++ [ "subtext0" "surface2" ] ++ accents ++ [ "subtext1" ];

  # Generates text suitable for a Ghostty config file.
  ghostty = palette: ''
    # Generated by dotfiles/lib/themes.nix — ${palette.variant} variant
    background = ${palette.colors.base}
    foreground = ${palette.colors.text}

    cursor-color = ${palette.colors.rosewater}
    cursor-text = ${palette.colors.crust}

    selection-background = ${palette.colors.surface0}
    selection-foreground = ${palette.colors.text}

    ${lib.concatStringsSep "\n" (lib.imap0
      (i: slot: "palette = ${toString i}=${palette.colors.${slot}}")
      (ansiSlots palette))}
  '';

  # Firefox browser chrome (toolbar/tabs/urlbar). Chrome only — page content is
  # deliberately untouched (spec decision 3). Requires
  # toolkit.legacyUserProfileCustomizations.stylesheets = true, set in
  # firefox.nix; without it Firefox ignores userChrome.css entirely.
  #
  # Custom properties use an --eminix- prefix, not --ctp- (Catppuccin): this
  # generator also renders high-contrast-dark/-light, which are explicitly
  # NOT Catppuccin (see that palette's own comment above), so a --ctp- name
  # would read as a bug when inspecting computed styles under those themes.
  # --eminix- matches this repo's own naming vocabulary instead of any one
  # palette's.
  #
  # Every rule below indexes 8 fixed palette slots by name (base, mantle,
  # crust, text, subtext0, surface0, surface1, blue). All four current
  # palettes define all eight, so nothing breaks today; a future palette
  # missing one of them fails loudly at Nix eval time with "attribute
  # missing" rather than silently rendering broken CSS. That's an acceptable
  # failure mode — just noting the coupling so it doesn't surprise anyone
  # adding a fifth palette.
  #
  # Every rule uses !important, and that is required, not stylistic: these
  # selectors compete against Firefox's own chrome (UA) stylesheet, which
  # re-applies its rules on state changes such as tab selection, hover, and
  # theme switches. Firefox's own rules on these elements are equal or higher
  # specificity, so without !important a "cleanup" that drops it will make
  # the override silently stop applying on some or all of those state
  # changes, with no error to flag it.
  firefoxChrome = palette: ''
    /* Generated by dotfiles/lib/themes.nix — ${palette.variant} variant */
    :root {
      --eminix-base: ${palette.colors.base};
      --eminix-mantle: ${palette.colors.mantle};
      --eminix-crust: ${palette.colors.crust};
      --eminix-text: ${palette.colors.text};
      --eminix-subtext0: ${palette.colors.subtext0};
      --eminix-surface0: ${palette.colors.surface0};
      --eminix-surface1: ${palette.colors.surface1};
      --eminix-accent: ${palette.colors.blue};
    }

    #navigator-toolbox {
      background-color: var(--eminix-mantle) !important;
      border-bottom: 1px solid var(--eminix-surface0) !important;
    }

    #TabsToolbar, #nav-bar, #PersonalToolbar {
      background-color: var(--eminix-mantle) !important;
      color: var(--eminix-text) !important;
    }

    .tabbrowser-tab .tab-content {
      color: var(--eminix-subtext0) !important;
    }

    .tabbrowser-tab[selected] .tab-content {
      color: var(--eminix-text) !important;
    }

    .tabbrowser-tab[selected] .tab-background {
      background-color: var(--eminix-base) !important;
      border-top: 2px solid var(--eminix-accent) !important;
    }

    #urlbar, #searchbar {
      background-color: var(--eminix-surface0) !important;
      color: var(--eminix-text) !important;
      border: 1px solid var(--eminix-surface1) !important;
    }

    #urlbar[focused="true"] {
      border-color: var(--eminix-accent) !important;
    }

    #sidebar-box, #sidebar-header {
      background-color: var(--eminix-mantle) !important;
      color: var(--eminix-text) !important;
    }
  '';

  # swaylock config (colors are RRGGBB[AA], no leading '#').
  # Ring/text states follow upstream catppuccin/swaylock conventions.
  swaylock = palette:
    let c = name: builtins.substring 1 6 palette.colors.${name};
    in ''
      ignore-empty-password
      indicator-radius=100
      indicator-idle-visible
      color=${c "crust"}
      inside-color=${c "base"}
      inside-clear-color=${c "base"}
      inside-ver-color=${c "base"}
      inside-wrong-color=${c "base"}
      ring-color=${c "lavender"}
      ring-clear-color=${c "rosewater"}
      ring-caps-lock-color=${c "peach"}
      ring-ver-color=${c "blue"}
      ring-wrong-color=${c "maroon"}
      key-hl-color=${c "green"}
      bs-hl-color=${c "rosewater"}
      text-color=${c "text"}
      text-clear-color=${c "rosewater"}
      text-caps-lock-color=${c "peach"}
      text-ver-color=${c "blue"}
      text-wrong-color=${c "maroon"}
      line-color=00000000
      line-clear-color=00000000
      line-ver-color=00000000
      line-wrong-color=00000000
      separator-color=00000000
    '';

  # Slot order for the [palette] section. Ported verbatim from the retired
  # bin/gen-theme-dir.py; kept for stable, readable diffs of the generated
  # colors.toml — the committed tree that generator once matched is gone, so
  # nothing else must match this order any more.
  paletteOrder = [
    "rosewater"
    "flamingo"
    "pink"
    "mauve"
    "red"
    "maroon"
    "peach"
    "yellow"
    "green"
    "teal"
    "sky"
    "sapphire"
    "blue"
    "lavender"
    "text"
    "subtext1"
    "subtext0"
    "overlay2"
    "overlay1"
    "overlay0"
    "surface2"
    "surface1"
    "surface0"
    "base"
    "mantle"
    "crust"
  ];

  # [ui] section: semantic name -> palette slot.
  uiSlots = [
    { key = "accent"; slot = "blue"; }
    { key = "foreground"; slot = "text"; }
    { key = "background"; slot = "base"; }
    { key = "cursor"; slot = "rosewater"; }
    { key = "selection_foreground"; slot = "base"; }
    { key = "selection_background"; slot = "rosewater"; }
  ];

  # colors.toml — the runtime single source of truth every themed app reads.
  colorsToml = name: palette:
    let
      c = palette.colors;
      line = k: v: ''${k} = "${v}"'';
      ui = map (e: line e.key c.${e.slot}) uiSlots;
      ansi = lib.imap0 (i: slot: line "color${toString i}" c.${slot}) (ansiSlots palette);
      pal = map (slot: line slot c.${slot}) paletteOrder;
    in
    lib.concatStringsSep "\n"
      (
        [
          "# ${name} - single source of truth for all themed apps."
          "# GENERATED by eminix lib/themes.nix — do not hand-edit."
          "# Change the palette in lib/themes.nix and rebuild."
          ""
          "[ui]"
        ] ++ ui ++ [ "" "[ansi]" ] ++ ansi ++ [ "" "[palette]" ] ++ pal
      ) + "\n";

  # btop.theme — template substitution. btop has 42 entries drawing on ~17
  # palette slots, so a template is clearer than a Nix string with 42 holes.
  #
  # The template's own leading comment block documents the template for
  # readers of btop.theme.in; it is not part of btop's file format and must
  # not reach generated output. It is stripped here at a marker line rather
  # than by a hardcoded line count, so editing that comment block cannot
  # silently leak it into every theme's btop.theme.
  btop = palette:
    let
      slots = lib.attrNames palette.colors;
      from = map (s: "@${s}@") slots;
      to = map (s: palette.colors.${s}) slots;
      raw = builtins.readFile ./templates/btop.theme.in;
      marker = "@@EMINIX-TEMPLATE-HEADER-END@@\n";
      parts = lib.splitString marker raw;
      body =
        if builtins.length parts == 2
        then builtins.elemAt parts 1
        else throw "btop.theme.in: expected exactly one @@EMINIX-TEMPLATE-HEADER-END@@ marker";
    in
    "# GENERATED by eminix lib/themes.nix — do not hand-edit.\n"
    + builtins.replaceStrings from to body;

  # gtk.conf — sourced by dot-theme-set, so key=value with no quoting games.
  gtk = name: palette:
    let dark = palette.variant == "dark"; in
    lib.concatStringsSep "\n" [
      "# GTK + system color-scheme for ${name}"
      "# Consumed by dot-theme-set via `source` - exports key=value vars."
      "# GENERATED by eminix lib/themes.nix — do not hand-edit."
      ''GTK_THEME="${if dark then "Adwaita-dark" else "Adwaita"}"''
      ''COLOR_SCHEME="${if dark then "prefer-dark" else "prefer-light"}"''
    ] + "\n";

  # Given a NAME and palette, produce the full theme config set. The name is
  # needed because the generated files carry it in their header comments.
  mkTheme = name: palette: {
    ghostty = ghostty palette;
    swaylock = swaylock palette;
    firefoxChrome = firefoxChrome palette;
    variant = palette.variant;
    colors = palette.colors;
    colorsToml = colorsToml name palette;
    gtk = gtk name palette;
    btop = btop palette;
  };
}
