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
      # Strict clean home (user rule): only Downloads, dotfiles, projects, docs
      # may exist at $HOME. Every XDG dir either maps onto one of those or is
      # null so createDirectories cannot mint a new top-level dir. NB: the
      # `projects` default is /home/scott/Projects — it MUST be set, or HM
      # recreates a capital-P duplicate of ~/projects on every activation.
      documents = "$HOME/docs";
      download = "$HOME/Downloads";
      projects = "$HOME/projects";
      # Screenshot/image tools get a valid target instead of falling back to
      # $HOME (the XDG default when a dir is unset) and littering it.
      pictures = "$HOME/Downloads";
      music = null;
      videos = null;
      desktop = null;
      publicShare = null;
      templates = null;
    };
  };
}
