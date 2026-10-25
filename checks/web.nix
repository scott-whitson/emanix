# The web editing layer's unit tests: template-file detection, mode dispatch and
# the formatter selection. emanix-web.el soft-requires web-mode and apheleia, so
# the batch Emacs here carries both -- the tests assert against the real
# packages rather than a stubbed absence. The html and css grammars are on
# LD_LIBRARY_PATH because the dispatch tests (one of them in a subprocess)
# choose html-ts-mode only when the html grammar is loadable.
#
# `pkgs' HERE IS NOT THE FLAKE'S `pkgs'. As with checks/prose.nix, flake.nix
# passes it the shared overlay-extended `emacsPkgs', defined in the top-level
# `let'.
{ pkgs, ... }:
let
  emacsPackages = pkgs.emacsPackagesFor pkgs.emacs-unstable-nox;
  emacsWithWebDeps =
    emacsPackages.emacsWithPackages
      (epkgs: [
        epkgs.web-mode
        epkgs.apheleia
      ]);
  grammars = emacsPackages.treesit-grammars.with-grammars
    (g: [ g.tree-sitter-html g.tree-sitter-css ]);
in
pkgs.runCommand "emanix-web-tests" { } ''
  export HOME=$(mktemp -d)
  export LD_LIBRARY_PATH=${grammars}/lib
  ${emacsWithWebDeps}/bin/emacs -Q --batch \
    -L ${../emacs/lisp} \
    -l ert \
    -l ${../emacs/test/emanix-web-test.el} \
    -f ert-run-tests-batch-and-exit
  touch $out
''
