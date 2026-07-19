{ config, lib, pkgs, ewm, ... }:

let
  emacsPkgs = import ./emacs/packages.nix { inherit pkgs; };
  # The ONE eminix Emacs: our package set (packages.nix) + EWM's module,
  # org pinned. This is the sole emacs-pgtk build — Home Manager delivers
  # config only (see emacs.nix). Exposed on the system PATH below so
  # emacsclient is available (EDITOR/VISUAL point at it via zsh.nix).
  theEmacs =
    ((pkgs.emacsPackagesFor pkgs.emacs-pgtk).overrideScope emacsPkgs.orgOverride).emacsWithPackages (epkgs: emacsPkgs.list epkgs ++ [ config.programs.ewm.ewmPackage ]);
in
{
  imports = [ "${ewm}/nix/service.nix" ];

  # Autologin scott on the console — LUKS already gates the machine, and the
  # tty1 launch hook below takes over the session to start EWM.
  services.getty.autologinUser = "scott";

  programs.ewm = {
    enable = true;
    emacsPackage = theEmacs;

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
        # starves every new launch. NB: the nix wrapper truncates comm to
        # '.emacs-30.2-wra', so match the full command line, never -x emacs.
        pkill -u "$USER" -f "bin/emacs --fg-daemon" 2>/dev/null && sleep 1
        _t0=$(date +%s)
        # XKB_DEFAULT_OPTIONS: wlroots reads this when it builds the keymap at
        # compositor start, so keyboard xkb opts (CapsLock->Control) apply
        # reliably — ewm-input-config's :xkb-options loads too late (after the
        # keymap is already built) to take effect.
        env LIBSEAT_BACKEND=logind XKB_DEFAULT_OPTIONS=ctrl:nocaps /run/current-system/sw/bin/ewm-launch
        # pgtk emacs DETACHES from the wrapper on daemon start. This login
        # session is the seat lease — hold it open while the daemon lives,
        # or the compositor loses DRM master the moment we exit.
        sleep 2
        while pgrep -u "$USER" -f "bin/emacs --fg-daemon" >/dev/null 2>&1; do sleep 3; done
        if [ $(( $(date +%s) - _t0 )) -lt 15 ]; then
          touch /tmp/.ewm-flap   # died fast — next login gets a shell
        fi
        exit 0                   # end session; autologin relaunches
      fi
    fi
  '';

  # Required by EWM: Mesa/EGL for the compositor's graphics backend.
  hardware.graphics.enable = true;

  # ni reads this to load the sqlite-vec (vec0) extension into ELISA's DB;
  # keeps the /nix/store path in Nix so the liveElisp scott-ni.el stays
  # store-path-free. Present in the login shell → inherited by the EWM daemon.
  environment.sessionVariables.ELISA_VEC0_PATH = "${pkgs.sqlite-vec}/lib/vec0.so";

  # EWM runtime deps + the single Emacs (gives emacsclient on the system PATH).
  environment.systemPackages = with pkgs; [
    theEmacs
    wl-clipboard
    brightnessctl
    # Screen lock (ext-session-lock): swayidle fires swaylock on logind's
    # before-sleep (lid close → suspend) and on loginctl lock-session.
    # swayidle is started from emacs (lisp/scott-ewm.el) so it inherits
    # WAYLAND_DISPLAY and dies with the session. Config: swaylock.nix (HM).
    swaylock
    swayidle
  ];

  # Without a PAM service entry swaylock can lock but never UNLOCK.
  security.pam.services.swaylock = { };
}
