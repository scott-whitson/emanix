# The theme switch's unit tests. Emacs owns the runtime theme as of
# 2026-09-11, so this is the guard on the thing that used to be a shell script
# nobody could test at all.
#
# No dbus, no systemd, no gsettings and no network: every side effect is
# stubbed, and the fixtures build their own theme tree and state directory in
# temp dirs.
{ pkgs, ... }:
pkgs.runCommand "theme-switch-tests" { } ''
  export HOME=$(mktemp -d)
  ${pkgs.emacs-nox}/bin/emacs -Q --batch \
    -L ${../emacs/lisp} \
    -l ert \
    -l cl-lib \
    -l ${../emacs/test/emanix-theme-test.el} \
    -f ert-run-tests-batch-and-exit
  touch $out
''
