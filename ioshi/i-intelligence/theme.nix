{ config, lib, pkgs, ... }:

{
  options.scott = {
    theme = lib.mkOption {
      type = lib.types.str;
      default = "catppuccin-mocha";
      description = "Active theme name (must match a key in lib/themes.nix palettes)";
    };

    dotfiles = {
      path = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/projects/dotfiles";
        description = "Path to the dotfiles repo";
      };
      enableSync = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable dot-sync timer";
      };
      profile = lib.mkOption {
        type = lib.types.str;
        default = "desktop";
        description = "Dotfiles profile name (desktop, server, wsl)";
      };
      liveElisp = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Symlink emacs elisp out-of-store from the dotfiles checkout for live editing. Disable on hosts with no checkout; elisp is then copied into the store (edits need a rebuild).";
      };
    };
  };

  # Theme options are consumed by other modules via `config.scott.theme`.
  # The theme library functions are passed via `dotfilesLib.theme` (set in flake.nix).
}