{ config, lib, pkgs, ... }:

{
  # Mako has fixed colors for now (theme integration via dotfilesLib if needed).
  services.mako = {
    enable = true;
    font = "JetBrainsMono Nerd Font 10";
    backgroundColor = "#1e1e2e";
    textColor = "#cdd6f4";
    borderColor = "#89b4fa";
    borderSize = 2;
    borderRadius = 4;
    padding = "12";
    margin = "8";
    defaultTimeout = 5000;
    maxVisible = 3;
    layer = "overlay";
    anchor = "top-right";
    iconPath = "/usr/share/icons/hicolor";
    extraConfig = ''
      [urgency=high]
      border-color=#f38ba8
      default-timeout=0
    '';
  };
}
