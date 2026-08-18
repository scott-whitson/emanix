# The ONE eminix Emacs build. Owns the package set, the org pin, and the
# derivation itself — mkEmacs is the only way to build it.
#
# Until 2026-08-18 this file exported `orgOverride` and `list` and each
# consumer assembled its own emacsWithPackages from them, so ewm.nix and
# emacs-daemon.nix carried the same expression twice, differing only in the
# EWM package. Any change to the base derivation had to be made in both or
# workstation and WSL hosts quietly got different Emacsen. Callers now pass
# what differs and nothing else.
{ pkgs, ... }:
let
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
in
{
  # The sole build site. `extraPackages` carries the caller's difference —
  # ewm.nix appends EWM's own package, which this file cannot know about, so
  # the seam takes a value rather than naming a variant.
  mkEmacs = { extraPackages ? [ ] }:
    ((pkgs.emacsPackagesFor pkgs.emacs-pgtk).overrideScope orgOverride).emacsWithPackages
      (epkgs: list epkgs ++ extraPackages);

  # elisa's sqlite-vec extension. Exported because elisa is in `list` above,
  # so this file owns the dependency; the two consumers set it on different
  # tiers (system vs home sessionVariables) but must agree on the value.
  elisaVecPath = "${pkgs.sqlite-vec}/lib/vec0.so";
}
