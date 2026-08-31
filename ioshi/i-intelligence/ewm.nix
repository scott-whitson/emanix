{ config, lib, pkgs, ewm, ... }:

let
  emacsPkgs = import ./emacs/packages.nix { inherit pkgs; };
  # The EWM variant of the emanix Emacs: the shared build (emacs/packages.nix,
  # which owns the package set and the org pin) plus EWM's own package. The
  # non-EWM variant is emacs-daemon.nix, which calls the same builder with no
  # extras — so "sole build" is not this file's claim to make; the two differ
  # only by what is passed here. Home Manager delivers config only (emacs.nix).
  # Exposed on the system PATH below so emacsclient is available
  # (EDITOR/VISUAL point at it via zsh.nix).
  theEmacs = emacsPkgs.mkEmacs {
    extraPackages = [ config.programs.ewm.ewmPackage ];
  };
in
{
  imports = [ "${ewm}/nix/service.nix" ];

  # The EWM switch, stated ONCE. Importing this module means the system owns
  # the Emacs build, so the home layer must not also install the non-EWM pgtk
  # Emacs and start a user daemon — that would build two full emacs-pgtk
  # derivations and start the very daemon the tty1 launch hook below pkills.
  #
  # Set here rather than by hand in a consumer's host config (where it
  # lived until 2026-08-18, alongside the role's imports of this file) so the
  # two cannot disagree: the import IS the switch. A hard definition, not
  # mkDefault — this is an invariant of importing ewm.nix, not an opinion.
  home-manager.users.${config.emanix.username}.emanix.ewm.enable = true;

  # Autologin is OPT-IN, and defaults OFF.
  #
  # It used to be unconditional here, justified by "LUKS already gates the
  # machine". That premise is a property of the HOST, not of EWM: it holds on a
  # laptop with an encrypted disk, and fails on an unencrypted server, where
  # autologin means physical access alone yields a logged-in session — and from
  # there the backup credentials and the age identities that decrypt every
  # secret in the fleet.
  #
  # Importing this module must not silently decide that for a host, so the
  # decision moves to the host. mkDefault, so opting in is one plain line:
  #   services.getty.autologinUser = "scott";
  #
  # EWM still works fine without it: the tty1 launch hook below is
  # loginShellInit gated on tty1, so it fires on ANY tty1 login, not only an
  # automatic one. Autologin only decides whether the machine reaches EWM
  # unattended at boot. Without it, EWM exiting returns you to a login prompt
  # instead of relaunching — which is the behaviour a server should have.
  services.getty.autologinUser = lib.mkDefault null;

  programs.ewm = {
    enable = true;
    emacsPackage = theEmacs;

    # Point EWM at our Emacs config in the emanix checkout.
    # ~/.config/emacs is populated by home-manager in both liveElisp modes
    # (symlinks to the checkout, or store copies) — never point at the repo
    # directly; it does not exist on every host.
    extraEmacsArgs =
      "--init-directory ${config.users.users.${config.emanix.username}.home}/.config/emacs";
  };

  # XDG portal backend: EWM's own packaged portals.conf sets
  # `default=gnome;gtk;`, but xdg-desktop-portal-gnome cannot activate
  # outside a GNOME session. FileChooser (Firefox uploads, GTK apps) then
  # hard-fails with "Backend call failed: Could not activate remote peer
  # 'org.freedesktop.impl.portal.desktop.gnome'" and the dialog never
  # appears. Pin the preferred backend to GTK for every desktop, including
  # "ewm" (the per-desktop file beats the common one beats the packaged
  # one).
  xdg.portal.config = {
    common = { default = [ "gtk" ]; };
    ewm = { default = [ "gtk" ]; };
  };

  # dconf service: portal-gtk (and other GTK apps) persist settings through
  # dconf/GSettings. Without it every portal dialog logs "failed to commit
  # changes to dconf: The name is not activatable" — harmless noise, but it
  # also means window size / recent-file state is never remembered.
  programs.dconf.enable = true;

  environment = {
    # Launch EWM directly from the tty1 login shell, INSIDE the logind session
    # scope. The shipped systemd user unit runs outside any session and cannot
    # acquire DRM master without a display manager (verified on zord-old:
    # direct ewm-launch works, unit path gets EACCES / instant seat drop).
    # LIBSEAT_BACKEND=logind pinned so a stray seatd can never steal the pick.
    # EWM exit/crash ends the login; getty + autologin restart it.
    loginShellInit = ''
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
          # pgtk emacs DETACHES from the wrapper on daemon start. Import
          # session env vars into systemd so user services (xdg-desktop-portal,
          # etc.) inherit DISPLAY/WAYLAND_DISPLAY.
          sleep 2
          systemctl --user import-environment WAYLAND_DISPLAY DISPLAY 2>/dev/null || true
          while pgrep -u "$USER" -f "bin/emacs --fg-daemon" >/dev/null 2>&1; do sleep 3; done
          if [ $(( $(date +%s) - _t0 )) -lt 15 ]; then
            touch /tmp/.ewm-flap   # died fast — next login gets a shell
          fi
          exit 0                   # end session; autologin relaunches
        fi
      fi
    '';

    sessionVariables = {
      # arc reads this to load the sqlite-vec (vec0) extension into its DB;
      # keeps the /nix/store path in Nix so the liveElisp emanix-arc.el stays
      # store-path-free. Present in the login shell → inherited by the EWM daemon.
      # arc errors at database-open time if it is unset or points nowhere, which
      # is the loud failure this variable exists to make possible.
      ARC_VEC0_PATH = emacsPkgs.arcVecPath;

      # XWayland display — X11 apps (Steam, etc.) use this to find XWayland.
      # XWayland is started from the loginShellInit below, after the compositor
      # is up.
      DISPLAY = ":0";
    };

    # EWM runtime deps + the single Emacs (gives emacsclient on the system PATH).
    systemPackages = with pkgs; [
      theEmacs
      wl-clipboard
      brightnessctl
      # Screen lock (ext-session-lock): swayidle fires swaylock on logind's
      # before-sleep (lid close → suspend) and on loginctl lock-session.
      # swayidle is started from emacs (lisp/emanix-ewm.el) so it inherits
      # WAYLAND_DISPLAY and dies with the session. Config: swaylock.nix (HM).
      swaylock
      swayidle
      # XWayland — EWM is a wlroots compositor; X11 apps (Steam, etc.)
      # need this to run under Wayland.
      xwayland
    ];
  };

  # Required by EWM: Mesa/EGL for the compositor's graphics backend.
  hardware.graphics.enable = true;

  # Without a PAM service entry swaylock can lock but never UNLOCK.
  security.pam.services.swaylock = { };
}
