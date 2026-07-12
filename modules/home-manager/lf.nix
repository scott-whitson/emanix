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
      previewer = "~/.config/lf/pv.sh";
      cleaner = "~/.config/lf/cleaner.sh";
    };
    extraConfig = ''
      # Keybindings
      map <enter> open
      map <space> toggle
      map <c-c> quit
      map . set hidden!
      map / search

      # File associations
      cmd open ${{
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