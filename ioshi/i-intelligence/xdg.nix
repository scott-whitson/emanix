{ ... }:

{
  xdg = {
    enable = true;
    mime.enable = true;
    mimeApps.enable = true;

    userDirs = {
      enable = true;
      createDirectories = true;
      setSessionVariables = true;
      # Strict clean home (user rule): only downloads, projects, docs
      # may exist at $HOME. Every XDG dir either maps onto one of those or is
      # null so createDirectories cannot mint a new top-level dir. NB: the
      # `projects` default is ~/Projects — it MUST be set, or HM
      # recreates a capital-P duplicate of ~/projects on every activation.
      documents = "$HOME/docs";
      download = "$HOME/downloads";
      projects = "$HOME/projects";
      pictures = "$HOME/downloads";
      music = "$HOME/downloads";
      videos = "$HOME/downloads";
      desktop = null;
      publicShare = null;
      templates = null;
    };
  };
}
