_:

{
  programs.btop = {
    enable = true;
    settings = {
      # These seven are the settings that differ from btop's compiled-in
      # defaults; the rest of a btop-generated btop.conf already matches them,
      # so it isn't restated here. (This used to cite the stow-era
      # base/btop/.config/btop/btop.conf as the source of truth. That tree
      # has not existed since the move to Nix -- this module IS the source.)

      # btop is the only system monitor emanix installs. htop was dropped
      # 2026-09-10: two monitors for one job, and this is the configured one.
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
