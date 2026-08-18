{ config, lib, pkgs, ... }:

let
  # The palette set is the real constraint on eminix.theme, so the option's
  # type is derived from it rather than restating it in prose.
  palettes = (import ../../lib/themes.nix { inherit pkgs; }).palettes;
in
{
  options.eminix = {
    theme = lib.mkOption {
      # enum, not str: an unknown name used to build cleanly and then break at
      # RUNTIME — ghostty.nix seeds theme.conf by interpolating this value into
      # a symlink target, so a typo produced a dangling link and a ghostty that
      # could not load its config. Now it is an eval error naming the valid set.
      type = lib.types.enum (lib.attrNames palettes);
      default = "catppuccin-mocha";
      description = "Active theme name. Must be a key in lib/themes.nix palettes.";
    };

    gui = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Machine has a graphical session. Gates cursor theme, Wayland tools, GUI apps, swaylock, and ghostty config.";
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
        # The distro generates the runtime tree now (lib/theme-tree.nix), so
        # this defaults into the store rather than into the consumer's checkout.
        # It pointed at ${src.dotfilesPath}/themes from 2026-08-17 until
        # 2026-08-18, which was correct while the distro shipped no themes —
        # that premise is what generating them removes. Consumers with their own
        # tree still override this.
        default = toString (import ../../lib/theme-tree.nix { inherit pkgs; });
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
