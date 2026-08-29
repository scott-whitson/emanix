{ config, lib, ... }:

{
  # An eminix box with no desktop app suite. Not headless: it still gets EWM,
  # because every eminix system should come up into the same Emacs interface.
  # The compositor is cheap — ewm.nix adds the EWM package to the Emacs build
  # and a tty1 login hook, and pulls in none of os-system/desktop.nix (steam,
  # printing, pipewire, bluetooth). What a server omits is `eminix.gui` below,
  # which gates the GUI APPLICATIONS (firefox, mpv, ghostty, swaylock) — not
  # the compositor.
  #
  # Autologin stays OFF here: ewm.nix defaults it off precisely because these
  # boxes are not necessarily disk-encrypted, and a host that wants it sets
  # services.getty.autologinUser itself. So the console asks for a password,
  # and the tty1 hook starts EWM once you are in.
  imports = [
    ../../ioshi/os-system/server.nix
    ../../ioshi/i-intelligence/ewm.nix
  ];

  # mkDefault throughout: a role is the STARTING SHAPE for a host, not a
  # constraint on it. A consumer overriding one of these in extraModules is
  # making an informed choice (a GUI-capable WSL box, a server that does run
  # pi); a bare definition would meet them with "conflicting definition
  # values" and force mkForce. Invariants belong in assertions, not in
  # definitions a consumer cannot outrank.
  # No text-to-speech. Importing ewm.nix makes this box a graphical desktop as
  # far as nixos/modules/services/misc/graphical-desktop.nix is concerned, and
  # that module turns services.speechd ON — an accessibility default aimed at
  # desktops with someone sitting at them.
  #
  # It costs 0.7 GiB: speech-dispatcher -> espeak-ng -> mbrola -> mbrola-voices,
  # of which the voice data alone is 645 MiB. Measured on datacore: importing
  # ewm.nix took the closure 6.2 -> 7.4 GiB, and turning this off brought it to
  # 6.7 GiB. So MORE THAN HALF the apparent cost of "EWM on a server" was
  # text-to-speech that nothing here will ever call. EWM itself is 16.5 MiB.
  #
  # mkDefault, so a server that does want a screen reader just says so.
  services.speechd.enable = lib.mkDefault false;

  home-manager.users.${config.eminix.username} = {
    eminix.gui = lib.mkDefault false;
    eminix.pi.enable = lib.mkDefault false;
  };
}
