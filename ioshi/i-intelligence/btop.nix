_:

{
  programs.btop = {
    enable = true;
    settings = {
      # base/btop/.config/btop/btop.conf is what has actually been running;
      # these four disagreed with it and lost. The rest of that file is the
      # stock btop-generated default and already matches btop's compiled-in
      # defaults, so it isn't restated here.
      color_theme = "active";
      theme_background = true;
      vim_keys = false;
      rounded_corners = true;
      update_ms = 2000;
      proc_sorting = "cpu lazy";
      proc_tree = false;
    };
  };
}
