{ config, lib, pkgs, ... }:

{
  options.scott = {
    theme = lib.mkOption {
      type = lib.types.str;
      default = "catppuccin-mocha";
      description = "Active theme name (must match a key in lib/themes.nix palettes)";
    };

    gui = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Machine has a graphical session. Gates cursor theme, Wayland tools, GUI apps, swaylock, and ghostty config.";
    };

    standalone = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Home Manager runs standalone on a foreign distro (no NixOS layer): skip agenix-dependent files (pi auth.json symlink). Which Emacs to install is scott.ewm.enable's decision, not this flag's.";
    };

    ewm.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "This machine's Emacs is the system-owned EWM build (ewm.nix). When false, the home layer installs the non-EWM pgtk Emacs and runs the daemon as a systemd user service (standalone.nix).";
    };

    dotfiles = {
      path = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/projects/dotfiles";
        description = "Path to the dotfiles repo";
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
