# The prose renderer's unit tests: face remaps, the reading column,
# document magnification, and org-appear/org-modern integration.
#
# emanix-prose-mode is now org-only.  Markdown rendering is handled by
# markdown-modern.  The test depends on org, visual-fill-column,
# org-modern and org-appear.
#
# `pkgs' HERE IS NOT THE FLAKE'S `pkgs'. As with checks/agent-shell-api.nix,
# flake.nix passes it `pkgs.extend emacs-overlay.overlays.default'.
{ pkgs, ... }:
let
  emacsPackages = pkgs.emacsPackagesFor pkgs.emacs-nox;
  emacsWithProseDeps =
    emacsPackages.emacsWithPackages
      (epkgs: [ epkgs.visual-fill-column
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