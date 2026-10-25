{ config, lib, ... }:

let
  # Elisp lives in the repo and is symlinked out-of-store (liveElisp) so it can
  # be edited without a home-manager switch. The Emacs BUILD is system-owned
  # (modules/ewm.nix, from emacs/packages.nix) — this module
  # delivers config, and declares the one option the consumer needs to reach
  # that build.
  emacsDir = "${config.emanix.src.path}/emacs";
in
{
  options.emanix.emacs.extraPackages = lib.mkOption {
    type = lib.types.functionTo (lib.types.listOf lib.types.package);
    default = _: [ ];
    description = ''
      Emacs packages the consuming flake adds to the distribution's Emacs
      build, as a function of the package set: `epkgs: [ epkgs.s ]'.

      Takes the package set rather than a plain list so the consumer never
      names the Emacs variant — which base a host runs is the distribution's
      choice and stays its choice (the EWM tier gets the pwayl/Skia build, the
      rest a pgtk one). It exists because a consumer's own elisp may need a
      package the distribution cannot justify shipping to everyone.
    '';
  };

  # The base those packages are compiled against, for a consumer that has to
  # build something from the package set itself — dotfiles' ement, mu4e and kkp
  # land in the PROFILE (their elisp arrives through personal.el's load-path
  # bridge, not through extraPackages), so they had to name a variant to be
  # built at all, and named `pkgs.emacs-pgtk' while the EWM tier was moving to
  # pwayl 31.1. That is byte-code compiled by one Emacs and loaded by another.
  #
  # Set by whichever module owns this host's Emacs — modules/ewm.nix for the EWM
  # tier, home/emacs-daemon.nix for the rest — and deliberately WITHOUT a
  # default: a default here is a variant decision nobody made, which is how the
  # mismatch above survived, and a host that sets neither now fails to evaluate
  # instead of quietly building the wrong Emacs.
  options.emanix.emacs.base = lib.mkOption {
    type = lib.types.package;
    description = ''
      The Emacs derivation this host's Emacs packages are built from. Set by
      modules/ewm.nix (the pwayl/Skia build) on EWM hosts, and by
      home/emacs-daemon.nix (pgtk) everywhere else.
    '';
  };

  config = {
    # liveElisp: symlink into the checkout for live editing; otherwise copy the
    # elisp (which lives in-repo next to this module) into the store so hosts
    # without a checkout still get a working config.
    xdg.configFile = {
      "emacs/early-init.el".source =
        if config.emanix.src.liveElisp
        then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/early-init.el"
        else ../emacs/early-init.el;
      "emacs/init.el".source =
        if config.emanix.src.liveElisp
        then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/init.el"
        else ../emacs/init.el;
      "emacs/lisp".source =
        if config.emanix.src.liveElisp
        then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/lisp"
        else ../emacs/lisp;

      # config.el and fallback.el are deployed exactly like init.el. If fallback.el
      # is ever missing, the loader's (load ... :noerror) degrades to "no fallback"
      # silently — so a missing entry here would make the guard look fine until the
      # moment it is needed. tests/init-guard.sh builds its own cp-based tree with
      # all four files always present; it never symlinks init.el and never omits
      # config.el/fallback.el together, so it cannot see the gap a bare `git pull'
      # opens between this liveElisp symlink and these two xdg.configFile entries.
      "emacs/fallback.el".source =
        if config.emanix.src.liveElisp
        then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/fallback.el"
        else ../emacs/fallback.el;
      "emacs/config.el".source =
        if config.emanix.src.liveElisp
        then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/config.el"
        else ../emacs/config.el;
    };

    # NO ~/.emacs.d mirror: emacs PREFERS ~/.emacs.d over ~/.config/emacs when
    # both exist, splitting runtime state (a second org-roam.db). ~/.config/emacs
    # is the only config path; ~/.emacs.d must not exist.

    # Launcher entry: a graphical frame (-c) on the running daemon, pinned to
    # the Wayland GDK backend. `emacsclient' resolves through PATH -- NixOS has
    # no /usr/bin/emacsclient.
    home.file.".local/share/applications/emacsclient.desktop".text = ''
      [Desktop Entry]
      Categories=Development;TextEditor;
      Comment=Edit text
      Exec=env GDK_BACKEND=wayland emacsclient -c %F
      GenericName=Text Editor
      Icon=emacs
      Keywords=Text;Editor;
      MimeType=text/english;text/plain;text/x-makefile;text/x-c++hdr;text/x-c++src;text/x-chdr;text/x-csrc;text/x-java;text/x-moc;text/x-pascal;text/x-tcl;text/x-tex;application/x-shellscript;text/x-c;text/x-c++;
      Name=Emacs Client
      StartupWMClass=Emacsd
      Terminal=false
      Type=Application
    '';
  };
}
