# The ONE emanix Emacs build SITE. Owns the package set and the derivation —
# mkEmacs is the only way to build it. Which base it builds on is the caller's
# choice because it is the host's: the EWM tier runs the GPU build
# (emacs/pwayl.nix), the rest of the fleet a pgtk one, and both are the same
# Emacs version so that one package list and one set of checks describe every
# host.
#
# It used to also own an org ELPA pin, working around an emacs-overlay snapshot
# that resolved org with a stale hash. That override said "until inputs are
# regenerated upstream" and then outlived the condition: the 2026-09-01 overlay
# resolves org 9.8.10 correctly, while the override still forced 9.8.7's
# tarball URL — which GNU ELPA had rotated away, since it serves only each
# package's current version. The workaround became the outage. Every host
# failed to build with a 404 buried under a long dependency cascade, and it
# would have hit a fresh install even sooner.
#
# Lesson worth keeping: a pin that hardcodes an ELPA URL has an expiry date
# nobody writes down. If org ever needs pinning again, pin it to something
# content-addressed that upstream does not delete.
#
# Until 2026-08-18 this file exported `orgOverride` and `list` and each
# consumer assembled its own emacsWithPackages from them, so ewm.nix and
# emacs-daemon.nix carried the same expression twice, differing only in the
# EWM package. Any change to the base derivation had to be made in both or
# workstation and WSL hosts quietly got different Emacsen. Callers now pass
# what differs and nothing else.
{ pkgs, ... }:
let
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
    embark-consult # embark.el requires it itself once consult is loaded, and warns if absent
    corfu
    dirvish
    magit
    llm
    async
    plz # llm's HTTP dep
    # `s' used to sit here as the gdocs dependency. The gdocs workflow moved to
    # dotfiles on 2026-09-20, and the consumer now supplies `s' through
    # emanix.emacs.extraPackages — which is what that seam is for. Removed
    # 2026-09-20 so the distribution carries no package that exists for one
    # consumer's workflow.
    org-roam
    org
    catppuccin-theme
    # --- Markdown rendering (markdown-modern replaces markdown-mode) ---
    # markdown-modern is a full major mode (derived from text-mode) that renders
    # markdown inline using text properties and overlays, in the spirit of
    # org-modern.  It replaces both markdown-mode (the major mode) and the
    # markdown half of emanix-prose.el (face remaps, table boxes, reveal).
    (trivialBuild {
      pname = "markdown-modern";
      version = "2.0.0";
      src = pkgs.fetchFromGitHub {
        owner = "rjprins";
        repo = "markdown-modern";
        rev = "58e1d0e6cdeaa6c8610bb90acdf3ba3083e22ae1";
        hash = "sha256-i9I1jGr3ixbcOyRqpblCC+ehCfuMKzeUmTwB0V/+Auk=";
      };
      # The lisp/ files are not at the source root; copy them up so
      # trivialBuild's batch-byte-compile *.el finds them.
      preBuild = ''
        cp lisp/*.el .
      '';
      packageRequires = [ ];
    })
    # --- Prose rendering (emanix-prose.el) ---
    # Now org-only: markdown rendering is handled by markdown-modern.
    visual-fill-column # centered reading column; org prose buffers
    org-modern # bullets, block framing, tag/timestamp styling for org
    org-appear # reveal org emphasis markers at point

    # --- Agent shell (ACP) ---
    # Claude Code and pi as Emacs buffers rather than terminals. agent-shell
    # speaks ACP -- "LSP for coding agents" -- to the real CLI, so CLAUDE.md,
    # skills, plugins, hooks and settings permissions all still apply.
    #
    # Replaced claude-code-ide.el on 2026-09-07, which was a terminal in a side
    # window and needed websocket + web-server for its MCP server. Those two
    # had no other consumer and left with it; so did the Emacs MCP tools it
    # exposed (xref, imenu, project), a deliberate trade recorded in
    # docs/superpowers/specs/2026-09-07-agent-shell-acp-design.md.
    agent-shell
    acp # the protocol client agent-shell drives
    shell-maker # agent-shell's buffer/prompt substrate
    # ghostel is THE buffer terminal, C-c t. NOT agent-shell's -- a terminal
    # in its own right.
    #
    # vterm sat beside it as a fallback from 2026-08-25, on the reasoning that
    # ghostel puts a native Zig module in the critical path and a broken one
    # should cost a terminal rather than a working Emacs. That was a
    # time-boxed hedge ("retire vterm only once ghostel has weeks on it") and
    # the weeks happened: removed 2026-09-10. The hedge it replaced is still
    # in place and is the better one -- ghostty is installed on every host and
    # is an independent window that survives an Emacs wedge entirely, which a
    # second in-Emacs terminal never could.
    ghostel
    transient # magit needs it; listed since ghostel's menu uses it directly

    # --- Code editing ---
    # Emacs 31 already ships the hard parts: project.el, eglot (LSP client),
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
      # markdown-modern requires both grammars for tree-sitter parsing.
      g.tree-sitter-markdown
      g."tree-sitter-markdown-inline"
    ]))
  ];
in
{
  # The sole build site. Both arguments are the caller's difference, and
  # neither has a default:
  #
  #   base           this host's Emacs — emacs/pwayl.nix on EWM hosts, a pgtk
  #                  build elsewhere. Required, because a default here is a
  #                  variant decision made by accident: this used to hardcode
  #                  pkgs.emacs-pgtk, so a caller that wanted the GPU build had
  #                  no way to ask for it and no way to notice it did not get
  #                  it.
  #   extraPackages  what the caller adds on top of the shared list. ewm.nix
  #                  appends EWM's own package, which this file cannot know
  #                  about, so the seam takes a value rather than naming a
  #                  variant.
  mkEmacs = { base, extraPackages ? (_: [ ]) }:
    (pkgs.emacsPackagesFor base).emacsWithPackages
      (epkgs: list epkgs ++ extraPackages epkgs);

}
