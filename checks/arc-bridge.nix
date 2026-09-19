# The ARC compatibility bridge is tested without ARC, Ollama or a database.
# The distro owns this key/dispatch contract while its package pin catches up
# with the retrieval-only ARC surface. See emanix-arc-test.el.
{ pkgs, ... }:
pkgs.runCommand "emanix-arc-bridge-tests" { } ''
  export HOME=$(mktemp -d)
  export EMANIX_ARC_CONFIG=${../ioshi/i-intelligence/emacs/config.el}
  ${pkgs.emacs-nox}/bin/emacs -Q --batch \
    -L ${../ioshi/i-intelligence/emacs/lisp} \
    -L ${../ioshi/i-intelligence/emacs/test} \
    -l ert \
    -l emanix-arc-test \
    -f ert-run-tests-batch-and-exit
  touch $out
''
