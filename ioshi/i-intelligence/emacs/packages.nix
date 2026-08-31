# The ONE emanix Emacs build. Owns the package set, the org pin, and the
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
    ace-window # replaces other-window on C-x o: overlays an `aw-keys'
    # letter on each window once there are three or more. Depends on avy,
    # already listed directly above.
    vertico
    orderless
    consult
    marginalia
    embark
    embark-consult
    corfu
    dirvish
    magit
    llm
    # arc — the distro's bundled companion, replacing the ELISA fork that used
    # to sit here. Its canonical source is the author's public GitHub repo
    # (same person as this flake — intentional, not a leak: the repo is
    # public).
    #
    # Pinned by rev with a real hash, deliberately: there is no local-checkout
    # override. An earlier draft read ARC_DEV_SRC through `builtins.getEnv',
    # which flakes evaluate to "" unless the caller also passes `--impure' —
    # and then fell through to the pin with NO error, silently building the
    # pinned rev instead of the working tree someone had just edited. That is
    # the same silent config-vs-reality divergence that let the old assistant
    # index nothing for six weeks. To iterate on arc: commit, push, bump the
    # rev and hash here, rebuild. Slower, and it cannot lie to you.
    (trivialBuild {
      pname = "arc";
      version = "0.1.0";
      src = pkgs.fetchFromGitHub {
        owner = "scott-whitson";
        repo = "arc";
        rev = "268aa5e56f493c0ee2f8bab4484896f678d577e7";
        hash = "sha256-E7UrNUF2pqWiLTqKqKMoLGvOmLrj04uUMFBB+hREA2I=";
      };
      # arc.el's own Package-Requires, exactly: llm, async, plz, transient.
      # NOT ellama — arc renders its own answer buffer and dropped that
      # dependency, which is why ellama is no longer in this list at all.
      packageRequires = with epkgs; [ llm async plz transient ];
    })
    async # arc dep (Package-Requires); also loadable standalone for testing
    plz # arc/llm HTTP dep
    s # string manipulation library (gdocs dependency)
    org-roam
    org
    catppuccin-theme
    markdown-mode # transition: vault is still .md until the conversion sub-project
    # --- Prose rendering (emanix-prose.el) ---
    visual-fill-column # centered reading column; markdown/org prose buffers
    org-modern # bullets, block framing, tag/timestamp styling for org
    org-appear # reveal org emphasis markers at point (markdown's equivalent
    # is hand-rolled in emanix-prose.el — no package provides it)
    vterm # native module built by nix; M-x package-install can't do this
    weblorg # pure Emacs Lisp static site generator with org-roam support

    # --- Claude Code IDE (trial, 2026-08-24) ---
    # claude-code-ide itself is deliberately NOT here: it is not on MELPA and is
    # early-development software that moves weekly, so it lives as a git
    # checkout in ~/.config/emacs/site-lisp and config.el adds it to load-path.
    # A `git pull' updates it with no rebuild. These four are what it needs from
    # the store.
    ghostel # libghostty-vt terminal, the backend claude-code-ide recommends.
    # Native Zig module, so nix must build it for the same reason as vterm above:
    # upstream auto-downloads a prebuilt .so on first use and cannot write to
    # the store.
    websocket # claude-code-ide: MCP transport
    web-server # claude-code-ide: MCP HTTP server
    transient # claude-code-ide's menu. Already in the closure via magit; listed
    # anyway because claude-code-ide requires it directly.

    # --- Code editing ---
    # Emacs 30 already ships the hard parts: project.el, eglot (LSP client),
    # flymake, xref, python-ts-mode, html-ts-mode and css-ts-mode are all
    # built in — the last two only ever looked absent because this list
    # shipped no grammars for them.
    #
    # web-mode is the one deliberate exception to built-ins-first: no built-in
    # mode parses template tags inside HTML structure, and the Jinja2 in this
    # world is 134 plain .html files under templates/ directories. mhtml-mode
    # and html-ts-mode both treat {% block %} as text. jinja2-mode was
    # rejected as stale (last release 2022).
    nix-ts-mode # no Nix major mode is built in; the tree-sitter one is current
    apheleia # async format-on-save that preserves point and undo history
    web-mode # the only mode that parses {% %} INSIDE html structure; see below
    # Tree-sitter grammars. These land in <deps>/lib/*.so, which Emacs does NOT
    # search by default (verified 2026-08-07: without the treesit-extra-load-path
    # fixup in config.el the *-ts-modes silently fail to activate). Add a language
    # here AND nowhere else — config.el discovers whatever this list provides.
    (treesit-grammars.with-grammars (g: [
      g.tree-sitter-nix
      g.tree-sitter-python
      g.tree-sitter-html
      g.tree-sitter-css
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

  # arc's sqlite-vec extension. Exported because arc is in `list` above, so
  # this file owns the dependency; the two consumers set it on different tiers
  # (system vs home sessionVariables) but must agree on the value.
  #
  # The basename must stay exactly `vec0.so'. Emacs checks it against a
  # hardcoded allow-list before SQLite sees the file, and SQLite then derives
  # the entry point from it — a renamed copy fails through one gate loudly and
  # the other in total silence. arc checks `sqlite-load-extension's return
  # value and errors at database-open time rather than much later at first
  # query, but do not rename this.
  arcVecPath = "${pkgs.sqlite-vec}/lib/vec0.so";
}
