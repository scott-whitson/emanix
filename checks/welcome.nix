# The welcome buffer's unit tests: where the dismissal marker lives and how the
# config repo is detected. emanix-welcome.el requires nothing, so a plain batch
# Emacs runs it. The claims the buffer makes about key bindings are a different
# guard: see checks/welcome-keys.nix.
{ pkgs, ... }:
pkgs.runCommand "emanix-welcome-tests" { } ''
  export HOME=$(mktemp -d)
  ${pkgs.emacs-unstable-nox}/bin/emacs -Q --batch \
    -L ${../emacs/lisp} \
    -l ert \
    -l ${../emacs/test/emanix-welcome-test.el} \
    -f ert-run-tests-batch-and-exit
  touch $out
''
