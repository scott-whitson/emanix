{ config, lib, pkgs, ... }:

{
  xdg = {
    enable = true;
    mime.enable = true;
    mimeApps.enable = true;

    userDirs = {
      enable = true;
      createDirectories = true;
      setSessionVariables = true;
      documents = "$HOME/docs";
      download = "$HOME/Downloads";
      music = "$HOME/Music";
      pictures = "$HOME/Pictures";
      videos = "$HOME/Videos";
      desktop = null;
      publicShare = null;
      templates = null;
    };
  };
}
