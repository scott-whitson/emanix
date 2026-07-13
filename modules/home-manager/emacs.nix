{ config, lib, pkgs, ... }:

let
  # Temporary pin for the org ELPA tarball: the current nixpkgs/emacs-overlay
  # snapshot resolves org-9.8.6 with a stale hash, so we override the source
  # explicitly until the package set is regenerated upstream.
  orgSrc = pkgs.fetchurl {
    url = "https://elpa.gnu.org/packages/org-9.8.7.tar";
    sha256 = "sha256-bYBtYtZkvZYG1qhPWBTBcWoH0xW+NW4m4m5ime5w+vg=";
  };

  emacsOverrides = self: super: {
    org = super.org.overrideAttrs (_old: {
      src = orgSrc;
    });
  };
in

let
  # Elisp lives in the repo and is symlinked out-of-store so it can be
  # edited live without a home-manager switch. Packages stay declarative.
  emacsDir = "${config.scott.dotfiles.path}/modules/home-manager/emacs";
in
{
  programs.emacs = {
    overrides = emacsOverrides;
    enable = true;
    package = pkgs.emacs-pgtk; # native Wayland build
    extraPackages = epkgs: with epkgs; [
      meow
      vertico
      orderless
      consult
      marginalia
      embark
      embark-consult
      corfu
      dirvish
      magit
      org-roam
      catppuccin-theme
      markdown-mode # transition: vault is still .md until the conversion sub-project
      vterm # native module built by nix; M-x package-install can't do this
    ];
  };

  services.emacs = {
    # mkDefault: EWM hosts must disable this — EWM's emacs IS the daemon,
    # and two daemons race for the same server socket (loser exits; when
    # that's EWM's emacs, the whole compositor goes down with it).
    enable = lib.mkDefault true;
    client.enable = true;
    defaultEditor = true;
  };

  # liveElisp: symlink into the checkout for live editing; otherwise copy
  # the elisp (which lives in-repo, next to this module) into the store so
  # hosts without a dotfiles checkout still get a working emacs config.
  xdg.configFile."emacs/early-init.el".source =
    if config.scott.dotfiles.liveElisp
    then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/early-init.el"
    else ./emacs/early-init.el;
  xdg.configFile."emacs/init.el".source =
    if config.scott.dotfiles.liveElisp
    then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/init.el"
    else ./emacs/init.el;
  xdg.configFile."emacs/lisp".source =
    if config.scott.dotfiles.liveElisp
    then config.lib.file.mkOutOfStoreSymlink "${emacsDir}/lisp"
    else ./emacs/lisp;

  # Emacs is still starting from the legacy ~/.emacs.d path on this machine,
  # so keep compatibility symlinks there until the daemon is fully migrated.
  home.file.".emacs.d/early-init.el".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/emacs/early-init.el";
  home.file.".emacs.d/init.el".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/emacs/init.el";
  home.file.".emacs.d/lisp".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/emacs/lisp";

  # Override the generated GUI desktop entry so launcher invocations open a
  # terminal-backed client instead of the unsupported pgtk/X11 frame path.
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
