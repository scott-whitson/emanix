{ config, lib, pkgs, ewm, ... }:

{
  imports = [ "${ewm}/nix/service.nix" ];

  programs.ewm = {
    enable = true;

    # Build Emacs with our packages + EWM's module bundled in.
    # emacsPackagesFor replaces the removed top-level pkgs.emacsWithPackages
    # alias (and builds pgtk/Wayland emacs, right for a Wayland compositor).
    # The org override mirrors the ELPA pin in modules/home-manager/emacs.nix.
    emacsPackage = ((pkgs.emacsPackagesFor pkgs.emacs-pgtk).overrideScope (eself: esuper: {
      org = esuper.org.overrideAttrs (_old: {
        src = pkgs.fetchurl {
          url = "https://elpa.gnu.org/packages/org-9.8.7.tar";
          sha256 = "sha256-bYBtYtZkvZYG1qhPWBTBcWoH0xW+NW4m4m5ime5w+vg=";
        };
      });
    })).emacsWithPackages (epkgs:
      (with epkgs; [
        meow vertico orderless consult marginalia embark embark-consult corfu
        dirvish magit org-roam org catppuccin-theme markdown-mode
      ])
      ++ [ config.programs.ewm.ewmPackage ]
    );

    # Point EWM at our Emacs config in the dotfiles repo.
    # ~/.config/emacs is populated by home-manager in both liveElisp modes
    # (symlinks to the checkout, or store copies) — never point at the repo
    # directly; it does not exist on every host.
    extraEmacsArgs =
      "--init-directory /home/scott/.config/emacs";
  };

  # Required by EWM: Mesa/EGL for the compositor's graphics backend.
  hardware.graphics.enable = true;

  # EWM runtime deps
  environment.systemPackages = with pkgs; [
    wl-clipboard
    brightnessctl
  ];
}