{ config, lib, pkgs, ewm, ... }:

{
  imports = [ "${ewm}/nix/service.nix" ];

  programs.ewm = {
    enable = true;

    # Build Emacs with our packages + EWM's module bundled in.
    emacsPackage = pkgs.emacsWithPackages (epkgs:
      (with epkgs; [
        meow vertico orderless consult marginalia embark embark-consult corfu
        dirvish magit org-roam org catppuccin-theme markdown-mode
      ])
      ++ [ config.programs.ewm.ewmPackage ]
    );

    # Point EWM at our Emacs config in the dotfiles repo.
    extraEmacsArgs =
      "--init-directory /home/scott/dotfiles/modules/home-manager/emacs";
  };

  # Required by EWM: Mesa/EGL for the compositor's graphics backend.
  hardware.graphics.enable = true;

  # EWM runtime deps
  environment.systemPackages = with pkgs; [
    wl-clipboard
    brightnessctl
  ];
}