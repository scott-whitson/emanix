{ config, ... }:

let
  # Elisp lives in the repo and is symlinked out-of-store (liveElisp) so it can
  # be edited without a home-manager switch. The Emacs BUILD is system-owned
  # (ioshi/i-intelligence/ewm.nix, from emacs/packages.nix) — this module only
  # delivers config.
  emacsDir = "${config.eminix.src.path}/ioshi/i-intelligence/emacs";
in
{
  # liveElisp: symlink into the checkout for live editing; otherwise copy the
  # elisp (which lives in-repo next to this module) into the store so hosts
  # without a checkout still get a working config.
  xdg.configFile."emacs/early-init.el".source =
    if config.eminix.src.liveElisp
    then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/early-init.el"
    else ./emacs/early-init.el;
  xdg.configFile."emacs/init.el".source =
    if config.eminix.src.liveElisp
    then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/init.el"
    else ./emacs/init.el;
  xdg.configFile."emacs/lisp".source =
    if config.eminix.src.liveElisp
    then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/lisp"
    else ./emacs/lisp;

  # config.el and fallback.el are deployed exactly like init.el. If fallback.el
  # is ever missing, the loader's (load ... :noerror) degrades to "no fallback"
  # silently — so a missing entry here would make the guard look fine until the
  # moment it is needed. tests/init-guard.sh builds its own cp-based tree with
  # all four files always present; it never symlinks init.el and never omits
  # config.el/fallback.el together, so it cannot see the gap a bare `git pull'
  # opens between this liveElisp symlink and these two xdg.configFile entries.
  xdg.configFile."emacs/fallback.el".source =
    if config.eminix.src.liveElisp
    then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/fallback.el"
    else ./emacs/fallback.el;
  xdg.configFile."emacs/config.el".source =
    if config.eminix.src.liveElisp
    then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/config.el"
    else ./emacs/config.el;

  # NO ~/.emacs.d mirror: emacs PREFERS ~/.emacs.d over ~/.config/emacs when
  # both exist, splitting runtime state (a second org-roam.db). ~/.config/emacs
  # is the only config path; ~/.emacs.d must not exist.

  # Launcher entry: terminal-backed client, not the pgtk/X11 frame path.
  home.file.".local/share/applications/emacsclient.desktop".text = ''
    [Desktop Entry]
    Categories=Development;TextEditor;
    Comment=Edit text
    Exec=/usr/bin/env GDK_BACKEND=wayland /usr/bin/emacsclient -c %F
    GenericName=Text Editor
    Icon=emacs
    Keywords=Text;Editor;
    MimeType=text/english;text/plain;text/x-makefile;text/x-c++hdr;text/x-c++src;text/x-chdr;text/x-csrc;text/x-java;text/x-moc;text/x-pascal;text/x-tcl;text/x-tex;application/x-shellscript;text/x-c;text/x-c++;
    Name=Emacs Client
    StartupWMClass=Emacsd
    Terminal=false
    Type=Application
  '';
}
