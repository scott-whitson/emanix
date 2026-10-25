{ config, lib, pkgs, ewm, ... }:

let
  # EWM builds on Smithay, whose libdisplay-info-sys 0.3.0 requires
  # libdisplay-info < 0.4.0. When the base channel's default libdisplay-info is
  # already 0.3.x this needs no override; when the channel has moved to 0.4.0,
  # the libdisplay-info_0_3 compatibility attribute pins the older soname.
  # Scoped to the compositor's own build, NOT a global overlay: mesa, wlroots
  # and gamescope all want the default, so an overlay would rebuild the
  # graphics stack against the older library.
  pkgsEwm = pkgs.extend (_final: prev: {
    libdisplay-info = prev.libdisplay-info_0_3 or prev.libdisplay-info;
    libdisplay-info_0_3 = prev.libdisplay-info_0_3 or prev.libdisplay-info;
  });

  # Built here rather than from programs.ewm.ewmPackage's default: that default
  # is a `pkgs.callPackage` against the module's own pkgs, and default.nix takes
  # the library via `inherit (pkgs)`, so there is no per-package seam to
  # override — the scoped pkgs has to go in at the call.
  #
  # emacsPackage is passed explicitly as the GPU base — the same derivation
  # theEmacs is built from — which is what service.nix's default resolves to
  # anyway (`cfg.emacsPackage.emacs or ...`, and theEmacs.emacs IS that base).
  # It breaks the loop that would otherwise exist between theEmacs and the
  # option it feeds. It is also what compiles ewm.el (`default.nix`'s
  # `emacsPackage.pkgs.trivialBuild`), so it has to be the GPU build too:
  # byte-code from a pgtk Emacs would load, but the package set would drag a
  # second Emacs into the closure and the elisp would no longer be built by the
  # Emacs that loads it.
  #
  # ONE PATCH, for an upstream bug. See docs/decisions/ewm-patches.md for the
  # mechanism, the keysym numbers, the exit condition, and the second patch
  # that was retired.
  ewmSrc = pkgs.applyPatches {
    name = "ewm-patched";
    src = ewm;
    patches = [
      ../patches/ewm-keysym-hex.patch
    ];
  };

  # The compositor's Emacs. emacs/pwayl.nix carries the whole argument for how
  # it is built: emacs31 from emacs-overlay, the passthru reconnect, and why
  # upstream's withSkia is not used.
  pwaylEmacs = import ../emacs/pwayl.nix { inherit pkgs ewm; };

  ewmPkg = import "${ewmSrc}/nix/default.nix" {
    pkgs = pkgsEwm;
    withScreencastSupport = config.programs.ewm.screencast.enable;
    emacsPackage = pwaylEmacs;
  };

  emacsPkgs = import ../emacs/packages.nix { inherit pkgs; };
  # The EWM variant of the emanix Emacs: the shared build (emacs/packages.nix,
  # which owns the package set) on the GPU base, plus EWM's own package. The
  # non-EWM variant is emacs-daemon.nix, which calls the same builder on a pgtk
  # base with no extras — so "sole build" is not this file's claim to make; the
  # two differ by what is passed here and nothing else. Home Manager delivers
  # config only (emacs.nix). Exposed on the system PATH below so emacsclient is
  # available (EDITOR/VISUAL point at it via zsh.nix).
  theEmacs = emacsPkgs.mkEmacs {
    base = pwaylEmacs;
    # A function of the package set, not a list: the consumer's extras take the
    # same shape. Read from the HM submodule because the option is declared
    # there (home/emacs.nix) — see the hmCfg note below for why the
    # consumer-facing options live on the HM tier. EWM's own package is not
    # from the Emacs package set, so the two are concatenated.
    extraPackages = epkgs: [ ewmPkg ] ++ hmCfg.emanix.emacs.extraPackages epkgs;
  };

  # The user's HOME MANAGER config, read from the NixOS tier.
  #
  # `emanix.theme' and `emanix.src.themesDir' are declared in
  # home/theme.nix, which is a Home Manager module (it resolves
  # `config.home.homeDirectory'). There is no `config.emanix.src' at NixOS
  # level -- emanix.nix declares exactly one NixOS-tier option, `username' --
  # so the values have to be reached through the HM submodule. This module
  # already addresses that submodule by name for `emanix.ewm.enable' below;
  # this reads from it rather than writing to it.
  #
  # Re-deriving themesDir here from lib/theme-tree.nix instead would evaluate
  # without any cross-tier reach and be WRONG on exactly the hosts that matter:
  # a consumer with its own theme tree overrides the option, and a second
  # derivation would silently disagree with the one the shell and the daemon
  # both export.
  hmCfg = config.home-manager.users.${config.emanix.username};
in
{
  imports = [ "${ewm}/nix/service.nix" ];

  # The EWM switch, stated ONCE. Importing this module means the system owns
  # the Emacs build, so the home layer must not also install the non-EWM pgtk
  # Emacs and start a user daemon — that would build two full Emacs
  # derivations (one pwayl, one pgtk) and start the very daemon the tty1 launch
  # hook below pkills.
  #
  # Set here rather than by hand in a consumer's host config (where it
  # lived until 2026-08-18, next to its import of this file) so the
  # two cannot disagree: the import IS the switch. A hard definition, not
  # mkDefault — this is an invariant of importing ewm.nix, not an opinion.
  #
  # One statement rather than two dotted ones: the module system refuses a
  # second definition of the same dynamic key (`users.${config.emanix.username}')
  # from a single module, and that is the right shape here anyway — the two
  # settings below are one decision about which Emacs this host has.
  home-manager.users.${config.emanix.username} = {
    emanix.ewm.enable = true;

    # ...and the base a consumer's own Emacs packages are compiled against, so
    # it never names the variant itself (emanix.emacs.base, declared in
    # home/emacs.nix). Same hard-definition reasoning as the switch above: on
    # this host the GPU build IS the Emacs, and byte-code compiled against
    # anything else is byte-code for an interpreter that never loads it — which
    # is what dotfiles' profile-installed ement/mu4e/kkp were doing.
    # emacs-daemon.nix sets the pgtk base on hosts that do not import this
    # module.
    emanix.emacs.base = pwaylEmacs;
  };
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

    # Set explicitly so nothing reaches the module's own default, which would
    # build ewm-core against the unscoped libdisplay-info. Today the default is
    # only ever an option default and laziness keeps it unbuilt, but that is a
    # property of service.nix's current internals, not a guarantee.
    ewmPackage = ewmPkg;

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
    # EWM exit/crash ends the login; with autologin on, getty restarts it,
    # otherwise the login prompt returns.
    loginShellInit = ''
      if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
        if [ -e "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ewm-flap" ]; then
          echo "EWM flapped ($(cat "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ewm-flap" 2>/dev/null)) — normal shell (rm \"''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ewm-flap\" and log out to re-arm)"
        else
          # One EWM per boot-session: a stale daemon holds DRM master and
          # starves every new launch. NB: the nix wrapper truncates comm to 15
          # characters (it reads '.emacs-31.1-wra'), so match the full command
          # line, never `pkill -x emacs'.
          pkill -u "$USER" -f "bin/emacs --fg-daemon" 2>/dev/null && sleep 1
          # XKB_DEFAULT_OPTIONS: wlroots reads this when it builds the keymap at
          # compositor start, so keyboard xkb opts (CapsLock->Control) apply
          # reliably — ewm-input-config's :xkb-options loads too late (after the
          # keymap is already built) to take effect.
          # Launch in the BACKGROUND so the poll below runs WHILE the daemon
          # comes up. `--fg-daemon' does NOT detach (measured on rafik
          # 2026-10-24: the launcher stays in the foreground for the daemon's
          # whole life), so a foreground call only returns after Emacs has
          # already exited — every poll was a post-mortem that always read
          # "never started", even for a daemon that came up and died in 2s.
          env LIBSEAT_BACKEND=logind XKB_DEFAULT_OPTIONS=ctrl:nocaps /run/current-system/sw/bin/ewm-launch &
          _ewm_launcher=$!
          # Wait for the daemon rather than sleeping a fixed time: a cold first
          # boot is the slowest the machine will ever be, and a fixed sleep
          # there reads a healthy-but-slow start as a flap, writes the marker,
          # and leaves the desktop shell-only until someone deletes it by hand.
          # Bounded so a real crash-loop times out instead of hanging the login.
          # Session env vars are imported unconditionally — a no-op `|| true' if
          # the daemon never appeared — so user services (xdg-desktop-portal,
          # etc.) inherit DISPLAY/WAYLAND_DISPLAY.
          _ewm_started=0
          for _ in $(seq 1 30); do
            pgrep -u "$USER" -f "bin/emacs --fg-daemon" >/dev/null 2>&1 && { _ewm_started=1; break; }
            sleep 1
          done
          systemctl --user import-environment WAYLAND_DISPLAY DISPLAY 2>/dev/null || true
          # ...and give those services something to be ordered against.
          # xdg-desktop-portal has Requisite=graphical-session.target, and a
          # Requisite that is not ALREADY active fails the job outright instead
          # of pulling it in — with the target never started, every portal
          # activation died with "Dependency failed for Portal service" and
          # Firefox's file chooser never opened. Importing the environment above
          # was necessary but not sufficient. See the ewm-session target below
          # for why that target cannot simply be started here.
          systemctl --user start ewm-session.target 2>/dev/null || true
          if [ "$_ewm_started" = 0 ]; then
            # Never appeared inside the 30s poll. Kill the launcher so `wait'
            # below does not hang the login, then record the failure.
            kill "$_ewm_launcher" 2>/dev/null
            echo "daemon never started (30s poll timed out)" > "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ewm-flap"
          else
            # Daemon is up — wait for it to exit, then judge by how long it
            # lived from when it APPEARED, not from launch (which would
            # over-count a slow start).
            _ewm_appear=$(date +%s)
            while pgrep -u "$USER" -f "bin/emacs --fg-daemon" >/dev/null 2>&1; do sleep 3; done
            if [ $(( $(date +%s) - _ewm_appear )) -lt 15 ]; then
              echo "daemon started then died within 15s" > "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ewm-flap"   # died fast — next login gets a shell
            fi
          fi
          wait "$_ewm_launcher" 2>/dev/null
          # Tear the session targets down again. ewm-shutdown.target
          # Conflicts with both and is StopWhenUnneeded, so starting it stops
          # them and then goes away by itself. Without this they stay active
          # across a logout and the next session inherits units that think a
          # compositor is running.
          systemctl --user start ewm-shutdown.target 2>/dev/null || true
          exit 0                   # end session; autologin (if on) relaunches
        fi
      fi
    '';

    sessionVariables = {
      # Why these are here and not in zsh.nix.
      #
      # The EWM Emacs is started by the login shell, not by the user manager, so
      # neither Home Manager's `programs.zsh.sessionVariables' (~/.zprofile,
      # read after the /etc/zprofile snippet above) nor its
      # `systemd.user.sessionVariables' reach it. Measured on the live session
      # 2026-09-11:
      #   (getenv "EMANIX_THEMES_DIR")  => nil
      #   emanix-theme--themes-dir      => "~/dotfiles/themes"  (absent)
      # Every theme file read silently missed; the desktop had been running the
      # wrong colours. `environment.sessionVariables' works because of WHERE
      # NixOS puts it: it merges into `environment.variables' ->
      # /etc/set-environment, which /etc/zshenv sources, and zshenv runs before
      # zprofile — so the values exist by the time the snippet above runs
      # `ewm-launch'.
      #
      # Every variable below is read by Emacs through `getenv', so all of them
      # fail in the same silent way when unset. Only what is unique to each is
      # noted.
      EMANIX_THEMES_DIR = hmCfg.emanix.src.themesDir;

      # The host's build-time theme. `emanix-theme--seed-name' reads it to
      # converge a machine with no runtime state on the theme its flake
      # configures rather than on the distro default.
      EMANIX_THEME = hmCfg.emanix.theme;

      # Loads the sqlite-vec (vec0) extension into arc's DB. Kept in Nix so the
      # liveElisp emanix-arc.el stays store-path-free; arc errors at
      # database-open time if it is unset or points nowhere, which is the loud
      # failure this variable exists to make possible.
      ARC_VEC0_PATH = emacsPkgs.arcVecPath;

      # Helper-script dir. Read by emanix-ewm-slots.el's Firefox slot, config.el's
      # calendar-sync binding, and a consuming flake's personal.el for its own
      # scripts; each falls back to a bare relative path when it is missing,
      # which resolves nowhere.
      EMANIX_BIN_DIR = hmCfg.emanix.src.binDir;

      # The consumer's checkout (~/dotfiles). emanix-welcome.el reads it; without
      # it the welcome buffer falls through to /etc/nixos and reports "no config
      # repo yet" even on hosts that have one. See zsh.nix's EMANIX_DOTFILES.
      EMANIX_DOTFILES = hmCfg.emanix.src.dotfilesPath;

      # X11 apps (Steam, etc.) use this to find XWayland, which EWM serves
      # through xwayland-satellite (see systemPackages below).
      DISPLAY = ":0";
    };

    # EWM runtime deps + the single Emacs (gives emacsclient on the system PATH).
    # wl-clipboard comes from home/packages.nix's gui block.
    systemPackages = with pkgs; [
      theEmacs
      brightnessctl
      # Screen lock (ext-session-lock). swayidle fires swaylock on logind's
      # before-sleep (lid close → suspend) and on loginctl lock-session; it is
      # started from Emacs (lisp/emanix-ewm.el) so it inherits WAYLAND_DISPLAY
      # and dies with the session. Config: the runtime theme switcher symlinks
      # $EMANIX_THEMES_DIR/<name>/swaylock.conf — generated per palette by
      # lib/theme-tree.nix — onto ~/.config/swaylock/config. No Home Manager
      # module renders that path any more: a runtime path with two owners gets
      # renamed to .hm-bak at every activation (the trap ghostty.nix documents).
      swaylock
      swayidle
      # XWayland — EWM is a wlroots compositor; X11 apps (Steam, etc.)
      # need this to run under Wayland.
      xwayland
      # ...and what actually starts it. EWM does not exec Xwayland itself:
      # compositor/src/xwayland/satellite.rs holds the X11 sockets and spawns
      # `xwayland-satellite' by name when an X11 client first connects (const
      # XWAYLAND_SATELLITE). It is a SEPARATE package from xwayland; without it
      # every session logged
      #   error spawning xwayland-satellite, disabling integration:
      #   No such file or directory (os error 2)
      # and no X11 app could start — Steam and Factorio being the ones this host
      # cares about.
      xwayland-satellite
    ];
  };

  # The session target the login path starts, and the only way to raise
  # graphical-session.target — that one sets RefuseManualStart=yes and answers
  # `Operation refused, unit ... may be requested by dependency only', so it can
  # be activated as a dependency but never by name. BindsTo= implies Requires=,
  # so starting this pulls it in; in the other direction it binds this target's
  # lifetime to graphical-session.target, so EWM's own ewm-shutdown.target
  # (Conflicts= against both) tears them down on the way out.
  #
  # This is what xdg-desktop-portal was missing: it declares
  # Requisite=graphical-session.target, and a Requisite that is not already
  # active fails the job instead of pulling it in.
  systemd.user.targets.ewm-session = {
    description = "EWM session";
    documentation = [ "man:systemd.special(7)" ];
    bindsTo = [ "graphical-session.target" ];
    wants = [ "graphical-session-pre.target" ];
    after = [ "graphical-session-pre.target" ];
  };

  # Required by EWM: Mesa/EGL for the compositor's graphics backend.
  hardware.graphics.enable = true;

  # Without a PAM service entry swaylock can lock but never UNLOCK.
  security.pam.services.swaylock = { };
}
