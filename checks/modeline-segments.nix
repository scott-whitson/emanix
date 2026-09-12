# The tab-bar status bar's consumer extension point, unit-tested. A consuming
# flake's personal.el registers segments on `emanix/modeline-extra-segments';
# nothing in the distribution uses it, so without this check the seam would be
# asserted only by the one consumer that happens to have a checkout.
#
# No agent-shell, no network, no systemd -- the render path reads procfs and
# sysfs only, which a plain batch Emacs has.
{ pkgs, ... }:
pkgs.runCommand "modeline-segment-tests" { } ''
  export HOME=$(mktemp -d)
  ${pkgs.emacs-nox}/bin/emacs -Q --batch \
    -L ${../ioshi/i-intelligence/emacs/lisp} \
    -l ert \
    -l emanix-modeline \
    -l ${../ioshi/i-intelligence/emacs/test/emanix-modeline-test.el} \
    -f ert-run-tests-batch-and-exit
  touch $out
''
