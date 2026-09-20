{ config, lib, pkgs, ewm, ... }:

let
  # EWM builds on Smithay, whose libdisplay-info-sys 0.3.0 declares
  # `libdisplay-info < 0.4.0` in its system-deps metadata. nixpkgs moved
  # libdisplay-info 0.3.0 -> 0.4.0 on 2026-07-25 and added the
  # libdisplay-info_0_3 compatibility attribute the day after, for exactly this
  # case. Without it ewm-core dies at build time with pkg-config reporting the
  # library as "not found" — it IS found, at /lib/pkgconfig/libdisplay-info.pc;
  # what fails is the upper version bound, which `system-deps` reports as
  # absence. Reading the truncated build log rather than the full one sends you
  # looking for a missing file that is right there.
  #
  # Scoped to the compositor's own build, NOT a global overlay: mesa, wlroots
  # and gamescope all want 0.4.0, so an overlay would rebuild the graphics
  # stack against the older library. The closure carries both, which is
  # unremarkable — distinct sonames, a few hundred KiB.
  pkgsEwm = pkgs.extend (_final: prev: {
    libdisplay-info = prev.libdisplay-info_0_3;
  });

  # Built here rather than taken from programs.ewm.ewmPackage's default: that
  # default is a `pkgs.callPackage` against the module's own pkgs, and
  # default.nix takes the library via `inherit (pkgs)`, so there is no
  # per-package seam to override — the scoped pkgs has to go in at the call.
  #
  # emacsPackage is passed explicitly as emacs-pgtk, which is exactly what
  # service.nix's default resolves to (`cfg.emacsPackage.emacs or ...`, and
  # theEmacs.emacs IS emacs-pgtk) — so this changes nothing about which Emacs
  # builds the elisp, while breaking the loop that would otherwise exist
  # between theEmacs and the option it feeds.
  # EWM cannot bind a key Emacs reports only by number -- the media/vendor
  # keysyms in the XF86 0x1008xxxx block, which is how the dictation key on
  # this ThinkPad arrives. The elisp side cannot work around it, and a patch
  # that tried lived in personal.el for a while doing nothing:
  # `ewm--event-key-spec' sends a non-symbol :key as an INTEGER, and the
  # compositor's `keysym_from_value' reads an integer as a UNICODE CODEPOINT
  # (xkb::utf32_to_keysym). 0x10081247 is 268964423, far above Unicode's
  # 0x10FFFF, so it resolves to NoSymbol however it is spelled -- and sending
  # it as the string "0x10081247" instead reaches `resolve_keysym_from_name',
  # which tries the name as-is, hyphens-as-underscores, an XF86 prefix and a
  # lossy-name table, but never parses hex.
  #
  # So the fix has to be where the name is resolved. Upstream carries no such
  # parse; if it gains one, this patch is what to drop.
  # Second patch: `ewm-intercept-prefixes' declares :type with `character',
  # but its OWN DEFAULT holds ?\M-x (134217848) and ?\s-f (8388710), both
  # above `max-char' (4194303) -- a key event with a modifier bit is an
  # integer, not a character. Nothing validated the list until the personal
  # layer called `setopt' on it to add the dictation key, and then the
  # upstream default failed the upstream type on every startup. Widened to
  # accept integers.
  ewmSrc = pkgs.applyPatches {
    name = "ewm-patched";
    src = ewm;
    patches = [
      ../../patches/ewm-keysym-hex.patch
      ../../patches/ewm-intercept-type.patch
    ];
  };

  ewmPkg = import "${ewmSrc}/nix/default.nix" {
    pkgs = pkgsEwm;
    withScreencastSupport = config.programs.ewm.screencast.enable;
    emacsPackage = pkgs.emacs-pgtk;
  };

  emacsPkgs = import ./emacs/packages.nix { inherit pkgs; };
  # The EWM variant of the emanix Emacs: the shared build (emacs/packages.nix,
  # which owns the package set) plus EWM's own package. The non-EWM variant is
  # emacs-daemon.nix, which calls the same builder with no extras — so "sole
  # build" is not this file's claim to make; the two differ only by what is
  # passed here. Home Manager delivers config only (emacs.nix). Exposed on the
  # system PATH below so emacsclient is available (EDITOR/VISUAL point at it
  # via zsh.nix).
  theEmacs = emacsPkgs.mkEmacs {
    # A function of the package set, not a list: the consumer's extras take the
    # same shape. Read from the HM submodule because the option is declared
    # there (i-intelligence/emacs.nix) — see the hmCfg note below for why the
    # consumer-facing options live on the HM tier. EWM's own package is not
    # from the Emacs package set, so the two are concatenated.
    extraPackages = epkgs: [ ewmPkg ] ++ hmCfg.emanix.emacs.extraPackages epkgs;
  };

  # The user's HOME MANAGER config, read from the NixOS tier.
  #
  # `emanix.theme' and `emanix.src.themesDir' are declared in
  # i-intelligence/theme.nix, which is a Home Manager module (it resolves
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
    # EWM exit/crash ends the login; getty + autologin restart it.
    loginShellInit = ''
      if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
        if [ -e "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ewm-flap" ]; then
          echo "EWM flapped ($(cat "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ewm-flap" 2>/dev/null)) — normal shell (rm \"''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ewm-flap\" and log out to re-arm)"
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
          # pgtk emacs DETACHES from the wrapper on daemon start. Wait for the
          # daemon rather than assuming a fixed sleep is enough. The first boot
          # after an install is the slowest boot the machine will ever do --
          # compiling nothing but populating every cache cold -- and a fixed
          # sleep there reads a healthy (but slow) start as a flap, writes the
          # marker, and leaves the desktop shell-only until someone finds and
          # deletes it by hand. Bounded so a genuine crash-loop still times out
          # instead of hanging the login. Import session env vars into systemd
          # unconditionally (whether or not the daemon ever appeared — a no-op
          # ignored by `|| true` if it didn't) so user services
          # (xdg-desktop-portal, etc.) inherit DISPLAY/WAYLAND_DISPLAY.
          _ewm_started=0
          for _ in $(seq 1 30); do
            pgrep -u "$USER" -f "bin/emacs --fg-daemon" >/dev/null 2>&1 && { _ewm_started=1; break; }
            sleep 1
          done
          systemctl --user import-environment WAYLAND_DISPLAY DISPLAY 2>/dev/null || true
          # ...and give those services something to be ordered against.
          # xdg-desktop-portal has Requisite=graphical-session.target, and a
          # Requisite that is not ALREADY active fails the job outright rather
          # than pulling it in — so with the target never started, every portal
          # activation died with "Dependency failed for Portal service" and
          # Firefox's file chooser simply never opened. Importing the
          # environment above was necessary but not sufficient.
          #
          # It cannot be started directly -- graphical-session.target sets
          # RefuseManualStart=yes and answers `Operation refused, unit ... may
          # be requested by dependency only'. It has to be PULLED IN, which is
          # what ewm-session.target below is for: its BindsTo= implies
          # Requires=, so starting it activates graphical-session.target as a
          # dependency, which is allowed. That EWM ships ewm-shutdown.target,
          # whose whole content is Conflicts= against these two targets, is the
          # upstream half of the same arrangement.
          systemctl --user start ewm-session.target 2>/dev/null || true
          if [ "$_ewm_started" = 0 ]; then
            # The daemon never showed up inside the 30s poll above -- that IS
            # the failure this marker exists to record. Elapsed time is the
            # wrong signal here (the poll's own worst-case duration already
            # exceeds the 15s threshold below), so write the marker
            # unconditionally instead of trying to infer this case from a
            # stopwatch. Distinct wording so tty1 tells this apart from a
            # daemon that came up and died quickly.
            echo "daemon never started (30s poll timed out)" > "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ewm-flap"
          else
            # Daemon appeared at least once — the elapsed-time check is still
            # the right instrument for "came up and died quickly", so keep it
            # exactly as it was.
            while pgrep -u "$USER" -f "bin/emacs --fg-daemon" >/dev/null 2>&1; do sleep 3; done
            if [ $(( $(date +%s) - _t0 )) -lt 15 ]; then
              echo "daemon started then died within 15s" > "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ewm-flap"   # died fast — next login gets a shell
            fi
          fi
          # Tear the session targets down again. ewm-shutdown.target
          # Conflicts with both and is StopWhenUnneeded, so starting it stops
          # them and then goes away by itself. Without this they stay active
          # across a logout and the next session inherits units that think a
          # compositor is running.
          systemctl --user start ewm-shutdown.target 2>/dev/null || true
          exit 0                   # end session; autologin relaunches
        fi
      fi
    '';

    sessionVariables = {
      # The theme pair, delivered to the EWM Emacs specifically.
      #
      # zsh.nix exports both of these, but NEITHER reaches this Emacs. It is
      # launched from `loginShellInit' above, which NixOS writes into
      # /etc/zprofile -- and Home Manager's own ~/.zprofile, where its
      # `programs.zsh.sessionVariables' land, is read AFTER that. Its
      # `systemd.user.sessionVariables' do not help either: the EWM Emacs is
      # started by the login shell, not by the user manager.
      #
      # Measured on the live EWM session 2026-09-11:
      #   (getenv "EMANIX_THEMES_DIR")  => nil
      #   emanix-theme--themes-dir      => "~/dotfiles/themes"  (absent)
      # so every theme file read silently missed and the desktop had been
      # running the wrong colours. `environment.sessionVariables' is the fix
      # because of WHERE NixOS puts it: it merges into `environment.variables',
      # which lands in /etc/set-environment, which /etc/zshenv sources -- and
      # zshenv is read before zprofile, so the variables exist by the time the
      # snippet above runs `ewm-launch'.
      EMANIX_THEMES_DIR = hmCfg.emanix.src.themesDir;

      # The host's build-time theme, which `emanix-theme--seed-name' reads to
      # converge a machine with no runtime state on the theme its flake
      # actually configures rather than on the distro default.
      EMANIX_THEME = hmCfg.emanix.theme;

      # arc reads this to load the sqlite-vec (vec0) extension into its DB;
      # keeps the /nix/store path in Nix so the liveElisp emanix-arc.el stays
      # store-path-free. Present in the login shell → inherited by the EWM daemon.
      # arc errors at database-open time if it is unset or points nowhere, which
      # is the loud failure this variable exists to make possible.
      ARC_VEC0_PATH = emacsPkgs.arcVecPath;

      # Helper-script dir. Same mechanism as EMANIX_THEMES_DIR above and the
      # same symptom: unset here, getenv returns nil in this Emacs specifically.
      # emanix-ewm-slots.el's Firefox slot and config.el's calendar-sync
      # binding both resolve their target through this, falling back to a
      # bare relative path (which resolves nowhere) when it is missing; a
      # consuming flake's personal.el does the same for its own helper
      # scripts.
      EMANIX_BIN_DIR = hmCfg.emanix.src.binDir;

      # The consumer's own checkout (e.g. ~/dotfiles) — emanix-welcome.el
      # reads this to find the config repo (see zsh.nix's EMANIX_DOTFILES for
      # the full story). Same mechanism as above: without it, the welcome
      # buffer in this Emacs falls through to /etc/nixos and wrongly reports
      # "no config repo yet" even on hosts that have one.
      EMANIX_DOTFILES = hmCfg.emanix.src.dotfilesPath;

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
      # WAYLAND_DISPLAY and dies with the session. Config: the runtime theme
      # switcher (Emacs) symlinks $EMANIX_THEMES_DIR/<name>/swaylock.conf --
      # generated per palette by lib/theme-tree.nix -- onto
      # ~/.config/swaylock/config. No Home Manager module renders that path
      # anymore: a runtime path with two owners gets renamed to .hm-bak at
      # every activation, the trap ghostty.nix documents.
      swaylock
      swayidle
      # XWayland — EWM is a wlroots compositor; X11 apps (Steam, etc.)
      # need this to run under Wayland.
      xwayland
      # ...and the thing that actually starts it. EWM does not exec Xwayland
      # itself: compositor/src/xwayland/satellite.rs holds the X11 sockets and
      # spawns `xwayland-satellite' by name when an X11 client first connects
      # (const XWAYLAND_SATELLITE). It is a SEPARATE package from xwayland, and
      # without it every session logged
      #   error spawning xwayland-satellite, disabling integration:
      #   No such file or directory (os error 2)
      # and no X11 app could start at all — Steam and Factorio being the ones
      # this host cares about.
      xwayland-satellite
    ];
  };

  # The session target the login path starts, and the only way to get
  # graphical-session.target up: that one is RefuseManualStart=yes, so it can
  # be activated as a dependency but never by name. BindsTo= implies Requires=,
  # so starting this pulls it in -- and, in the other direction, binds this
  # target's lifetime to it, so EWM's own ewm-shutdown.target (Conflicts= with
  # graphical-session.target) tears both down on the way out.
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
