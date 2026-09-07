# The buffer-sync patch, unit-tested. This is the half of emanix-agent-shell.el
# with no agent-shell dependency -- deliberately, because it is also the half
# where every measured failure lived, and because that independence is what
# lets a plain batch Emacs run it on every `nix flake check'.
{ pkgs, ... }:
pkgs.runCommand "agent-shell-sync-tests" { } ''
  export HOME=$(mktemp -d)
  ${pkgs.emacs-nox}/bin/emacs -Q --batch \
    -L ${../ioshi/i-intelligence/emacs/lisp} \
    -l ert \
    -l emanix-agent-shell \
    -l emanix-agent-shell-tests \
    -f ert-run-tests-batch-and-exit
  touch $out
''
