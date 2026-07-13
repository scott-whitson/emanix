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

  # Launch EWM directly from the tty1 login shell, INSIDE the logind session
  # scope. The shipped systemd user unit runs outside any session and cannot
  # acquire DRM master without a display manager (verified on zord-old:
  # direct ewm-launch works, unit path gets EACCES / instant seat drop).
  # LIBSEAT_BACKEND=logind pinned so a stray seatd can never steal the pick.
  # EWM exit/crash ends the login; getty + autologin restart it.
  environment.loginShellInit = ''
    if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
      if [ -e /tmp/.ewm-flap ]; then
        echo "EWM flapped — normal shell (rm /tmp/.ewm-flap and log out to re-arm)"
      else
        # One EWM per boot-session: a stale daemon holds DRM master and
        # starves every new launch (pgtk daemon shows as bare 'emacs').
        pkill -u "$USER" -x emacs 2>/dev/null && sleep 1
        _t0=$(date +%s)
        env LIBSEAT_BACKEND=logind /run/current-system/sw/bin/ewm-launch
        # pgtk emacs DETACHES from the wrapper on daemon start. This login
        # session is the seat lease — hold it open while the daemon lives,
        # or the compositor loses DRM master the moment we exit.
        sleep 2
        while pgrep -u "$USER" -x emacs >/dev/null 2>&1; do sleep 3; done
        if [ $(( $(date +%s) - _t0 )) -lt 15 ]; then
          touch /tmp/.ewm-flap   # died fast — next login gets a shell
        fi
        exit 0                   # end session; autologin relaunches
      fi
    fi
  '';

  # Required by EWM: Mesa/EGL for the compositor's graphics backend.
  hardware.graphics.enable = true;

  # EWM runtime deps
  environment.systemPackages = with pkgs; [
    wl-clipboard
    brightnessctl
  ];
}