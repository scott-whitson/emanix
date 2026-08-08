{ config, lib, pkgs, ... }:

{
  programs.lf = {
    enable = true;
    settings = {
      shell = "zsh";
      idlefmt = "";
      icons = true;
      preview = true;
      hidden = true;
      drawbox = true;
      ratios = "1:2:3";
    };
    extraConfig = ''
      # base/lf/.config/lf/lfrc — carried over verbatim, this is the only
      # thing the stow twin actually configured.
      cmd yank-path $printf '%s' "$f" | wl-copy
      map y yank-path

      # Keybindings
      map <enter> open
      map <space> toggle
      map <c-c> quit
      map . set hidden!
      map / search

      # File associations
      cmd open ''${{
        case $(file --mime-type $f -b) in
          text/*) $EDITOR $fx;;
          image/*) imv $fx;;
          video/*) mpv $fx;;
          audio/*) mpv $fx;;
          application/pdf) zathura $fx;;
          *) for f in $fx; do xdg-open $f &> /dev/null &; done;;
        esac
      }}
    '';
  };
}

