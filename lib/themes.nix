{ pkgs, lib ? pkgs.lib, ... }:

rec {
  # Theme palette definitions and config generators.
  # Each theme is a palette + variant; each generator produces app config text.
  #
  # Usage from an HM module:
  #   lib.theme.generators.ghostty lib.theme.palettes.catppuccin-mocha
  #
  # Or from a host config:
  #   lib.theme.mkTheme lib.theme.palettes.catppuccin-mocha

  palettes = {
    catppuccin-mocha = {
      variant = "dark";
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
  # bin/gen-theme-dir.py must emit this same ordering.
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

  # Given a palette, produce the full theme config set.
  mkTheme = palette: {
    ghostty = ghostty palette;
    swaylock = swaylock palette;
    variant = palette.variant;
    colors = palette.colors;
  };
}
