# Single source of truth for the eminix Emacs package set + the org pin.
# Consumed by ioshi/i-intelligence/ewm.nix (the sole build site).
{ pkgs, ... }:
{
  # org ELPA pin — the current emacs-overlay snapshot resolves org with a
  # stale hash; override the source until inputs are regenerated upstream.
  orgOverride = _eself: esuper: {
    org = esuper.org.overrideAttrs (_old: {
      src = pkgs.fetchurl {
        url = "https://elpa.gnu.org/packages/org-9.8.7.tar";
        sha256 = "sha256-bYBtYtZkvZYG1qhPWBTBcWoH0xW+NW4m4m5ime5w+vg=";
      };
    });
  };

  list = epkgs: with epkgs; [
    meow
    avy
    vertico
    orderless
    consult
    marginalia
    embark
    embark-consult
    corfu
    dirvish
    magit
    ellama
    llm
    (elisa.overrideAttrs (_: {
      # elisa is the distro's bundled assistant; the canonical source is the
      # author's public GitHub repo (same person as this flake — intentional,
      # not a leak: the repo is public).
      src = pkgs.fetchFromGitHub {
        owner = "scott-whitson";
        repo = "elisa";
        rev = "61dab4eaa592132e17bf0c06562ddc450aeb5fb4";
        hash = "sha256-9dPYVT084JW1Q3BmLR5lA3lwxxb3Vi/s1DpkqxTdGGc=";
      };
    }))
    async # ELISA dep (Package-Requires); needed to load elisa.el for port testing
    plz # ELISA/llm HTTP dep
    s # string manipulation library (gdocs dependency)
    org-roam
    org
    catppuccin-theme
    markdown-mode # transition: vault is still .md until the conversion sub-project
    vterm # native module built by nix; M-x package-install can't do this
    weblorg # pure Emacs Lisp static site generator with org-roam support

    # --- Code editing ---
    # Emacs 30 already ships the hard parts: project.el, eglot (LSP client),
    # flymake, xref and python-ts-mode are all built in. Only these three are
    # actually missing.
    nix-ts-mode # no Nix major mode is built in; the tree-sitter one is current
    apheleia # async format-on-save that preserves point and undo history
    # Tree-sitter grammars. These land in <deps>/lib/*.so, which Emacs does NOT
    # search by default (verified 2026-08-07: without the treesit-extra-load-path
    # fixup in config.el the *-ts-modes silently fail to activate). Add a language
    # here AND nowhere else — config.el discovers whatever this list provides.
    (treesit-grammars.with-grammars (g: [
      g.tree-sitter-nix
      g.tree-sitter-python
    ]))
  ];
}
