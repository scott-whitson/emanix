# The runtime theme tree — one directory per palette, containing every file
# dot-theme-set and the elisp read at switch time.
#
# Until 2026-08-18 this tree was 32 files committed in the CONSUMER repo,
# produced by bin/gen-theme-dir.py which read this flake's palettes over
# `nix eval`. One source, one committed derivative, and after the
# distro/consumer split the pipeline could not even be run — the generator
# looked for ./lib/themes.nix in a repo that no longer had it. The distro holds
# every input, so it produces the tree itself.
{ pkgs, lib ? pkgs.lib }:
let
  themeLib = import ./themes.nix { inherit pkgs lib; };

  mkThemeDir = name: palette:
    let t = themeLib.mkTheme name palette; in
    pkgs.runCommand "emanix-theme-${name}" { } ''
      mkdir -p $out
      cp ${pkgs.writeText "colors.toml" t.colorsToml}   $out/colors.toml
      cp ${pkgs.writeText "gtk.conf" t.gtk}             $out/gtk.conf
      cp ${pkgs.writeText "btop.theme" t.btop}          $out/btop.theme
      printf '%s\n' ${lib.escapeShellArg t.variant}     > $out/variant
      printf '%s\n' ${lib.escapeShellArg palette.emacsTheme} > $out/emacs-theme
      # pi's theme JSON is 205 lines of colour logic (variant detection,
      # light/dark background maps, a think-text ramp). Reused as a script
      # rather than reimplemented in Nix. gen-pi-theme.py takes the "name"
      # field from its INPUT file's parent directory, not the output path, so
      # colors.toml is fed to it from a directory literally named "${name}"
      # (the store's own emanix-theme-${name} dir has a hash prefix that would
      # otherwise leak into pi-agent-theme.json's "name").
      mkdir -p ${name}
      cp $out/colors.toml ${name}/colors.toml
      ${pkgs.python3}/bin/python3 ${./gen-pi-theme.py} \
        ${name}/colors.toml $out/pi-agent-theme.json
    '';
in
pkgs.runCommand "emanix-themes" { } (''
  mkdir -p $out
'' + lib.concatStringsSep "\n"
  (lib.mapAttrsToList (n: p: "cp -r ${mkThemeDir n p} $out/${n}") themeLib.palettes))
