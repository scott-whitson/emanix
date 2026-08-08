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

    ewm.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "This machine's Emacs is the system-owned EWM build (ewm.nix). When false, the home layer installs the non-EWM pgtk Emacs and runs the daemon as a systemd user service (emacs-daemon.nix).";
    };

    role = lib.mkOption {
      type = lib.types.enum [ "workstation" "server" "wsl" ];
      default = "workstation";
      description = ''
        What shape of eminix box this is. Set by lib/mkHost.nix from the same
        `role` argument that selects profiles/roles/<role>.nix, so the option and
        the imported profile cannot drift apart.

        Replaced scott.dotfiles.profile on 2026-08-08, which encoded the same
        fact in a second vocabulary ("desktop" for what the role calls
        "workstation") and was set by hand in each role profile.
      '';
    };

    pi.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        This host actually runs the pi agent, so it gets the OpenRouter
        credential symlinked from agenix.

        Set false on hosts that hold ~/.pi/agent only as a Syncthing peer.
        datacore is the case this exists for: it is NOT a recipient of
        openrouter-auth.age (see secrets/secrets.nix) and has no /run/agenix at
        all, so deploying the symlink there would point at a secret it can never
        decrypt. Being a NixOS host with agenix is not the same as being a
        recipient of a given secret.
      '';
    };

    dotfiles = {
      path = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/projects/dotfiles";
        description = "Path to the dotfiles repo";
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
