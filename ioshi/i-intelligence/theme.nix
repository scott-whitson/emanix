{ config, lib, pkgs, ... }:

{
  options.eminix = {
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

        Replaced eminix.dotfiles.profile on 2026-08-08, which encoded the same
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

        Set false on hosts that hold ~/.pi/agent only as a Syncthing peer
        (they receive the secret via agenix — a recipient of the secret is a
        per-host agenix concern — but do not run pi, so there is no reason to
        deploy the symlink there). This option gates the symlink only; it
        does not gate, and never gated, recipient status.
      '';
    };

    src = {
      path = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/projects/eminix";
        description = "Path to the eminix source checkout (used for live-editable config).";
      };
      dotfilesPath = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/dotfiles";
        example = "/home/alice/projects/dotfiles";
        description = ''
          Path to the CONSUMER's checkout — the flake that imports eminix and
          supplies the personal layer. Distinct from src.path, which is the
          distro's own checkout.

          themesDir and binDir derive from this, because the distro ships
          neither themes/ nor bin/: both are consumer-supplied. Override this
          on a host whose consumer checkout is not ~/dotfiles.
        '';
      };
      themesDir = lib.mkOption {
        type = lib.types.str;
        # Derives from dotfilesPath, NOT src.path: the distro's checkout ships
        # no themes/ dir, so the old ${src.path}/themes default pointed at a
        # directory that exists on no machine.
        default = "${config.eminix.src.dotfilesPath}/themes";
        description = "Path to the themes directory the active-theme tooling reads from.";
      };
      binDir = lib.mkOption {
        type = lib.types.str;
        # Same reasoning as themesDir. The helper scripts (dot-theme-set,
        # calendar-sync, the firefox and pi wrappers) live in the consumer's
        # checkout; the distro ships no bin/.
        default = "${config.eminix.src.dotfilesPath}/bin";
        description = "Path to the helper-script directory put on PATH and resolved from elisp.";
      };
      liveElisp = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Symlink emacs elisp out-of-store from the eminix checkout for live editing. Disable on hosts with no checkout; elisp is then copied into the store (edits need a rebuild).";
      };
    };
  };

  # Theme options are consumed by other modules via `config.eminix.theme`.
  # The theme library functions are passed via `dotfilesLib.theme` (set in flake.nix).
}
