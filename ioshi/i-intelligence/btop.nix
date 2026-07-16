{ config, lib, pkgs, ... }:

{
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "catppuccin_mocha";
      theme_background = false;
      vim_keys = true;
      rounded_corners = true;
      update_ms = 2000;
      proc_sorting = "cpu direct";
      proc_tree = false;
    };
  };
}
