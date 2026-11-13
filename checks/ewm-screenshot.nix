# The PrintScreen command's unit tests. The orchestration -- when slurp runs,
# what grim is handed, what happens to the temp file -- is asserted with the
# three subprocesses stubbed, so a plain batch Emacs with no Wayland session,
# no grim and no clipboard is enough. See emacs/test/emanix-ewm-test.el.
{ pkgs, ... }:
pkgs.runCommand "ewm-screenshot-tests" { } ''
  export HOME=$(mktemp -d)
  ${pkgs.emacs-unstable-nox}/bin/emacs -Q --batch \
    -L ${../emacs/lisp} \
    -l ert \
    -l emanix-ewm-screenshot \
    -l ${../emacs/test/emanix-ewm-test.el} \
    -f ert-run-tests-batch-and-exit
  touch $out
''
