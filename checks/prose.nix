# The prose renderer's unit tests: the drawn markdown table, the reveal-at-
# point round trip, and document magnification.
#
# Unlike org-modern and org-appear (soft, `skip-unless'), markdown-mode and
# visual-fill-column are real test-time dependencies: the reading column and
# the table renderer both read their variables.
#
# `pkgs' HERE IS NOT THE FLAKE'S `pkgs'. As with checks/agent-shell-api.nix,
# flake.nix passes it `pkgs.extend emacs-overlay.overlays.default', because the
# table renderer reads markdown-mode internals -- markdown-table-colfmt,
# markdown--is-delimiter-row, markdown--remove-invisible-markup -- and a bare
# nixpkgs markdown-mode could differ from the one every host runs.
{ pkgs, ... }:
let
  emacsPackages = pkgs.emacsPackagesFor pkgs.emacs-nox;
  emacsWithProseDeps =
    emacsPackages.emacsWithPackages
      (epkgs: [ epkgs.markdown-mode
                epkgs.visual-fill-column
                epkgs.org-modern
                epkgs.org-appear ]);
in
pkgs.runCommand "emanix-prose-tests" { } ''
  export HOME=$(mktemp -d)
  ${emacsWithProseDeps}/bin/emacs -Q --batch \
    -L ${../emacs/lisp} \
    -l ert \
    -l ${../emacs/test/emanix-prose-test.el} \
    -f ert-run-tests-batch-and-exit
  touch $out
''