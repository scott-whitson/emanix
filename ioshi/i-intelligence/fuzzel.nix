{ config, lib, pkgs, ... }:

{
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "JetBrainsMono Nerd Font:size=12";
        # Colors set by theme module at runtime
        background = "1e1e2ee6";
        text-color = "cdd6f4";
        match-color = "89b4fa";
        selection-color = "45475a";
        border-color = "89b4fa";
        border-radius = 8;
        lines = 15;
        width = 40;
        placeholder = "Search...";
        terminal = "ghostty";
        launch-prefix = "uwsm app --";
      };
      dmenu = {
        exit-immediately-if-empty = false;
      };
    };
  };
}
