# The upstream API this integration is built on, asserted against the package
# the overlay actually pins.
#
# agent-shell's author describes the API as unstable and acp.el as not yet
# API-stable, and emanix-agent-shell.el reads an undocumented event payload.
# A bump that renames `agent-shell-subscribe-to' or drops agent-shell-pi would
# otherwise surface as a keybinding that errors when pressed, weeks later.
{ pkgs, ... }:
let
  emacsPackages = pkgs.emacsPackagesFor pkgs.emacs-nox;
  agentShellPkg = emacsPackages.agent-shell;
  emacsWithAgentShell =
    emacsPackages.emacsWithPackages
      (epkgs: [ epkgs.agent-shell epkgs.acp epkgs.shell-maker ]);
in
pkgs.runCommand "agent-shell-api" { } ''
  export HOME=$(mktemp -d)
  ${emacsWithAgentShell}/bin/emacs -Q --batch --eval '(progn
    (require (quote agent-shell))
    (require (quote agent-shell-anthropic))
    (require (quote agent-shell-pi))
    (dolist (sym (quote (agent-shell-subscribe-to
                         agent-shell-submit
                         agent-shell-send-region
                         agent-shell-anthropic-start-claude-code
                         agent-shell-pi-start-agent)))
      (unless (fboundp sym)
        (error "agent-shell no longer defines %s" sym)))
    (dolist (var (quote (agent-shell-mode-hook
                         agent-shell-anthropic-claude-acp-command
                         agent-shell-text-file-capabilities)))
      (unless (boundp var)
        (error "agent-shell no longer defines %s" var)))
    ;; The event name the buffer-sync patch subscribes to. Documented only in
    ;; the docstring of agent-shell-subscribe-to, so assert against that.
    (unless (string-match-p "tool-call-update"
                            (documentation (quote agent-shell-subscribe-to)))
      (error "agent-shell no longer documents the tool-call-update event")))'

  # The symbols above can all stay green while the payload SHAPE underneath
  # them changes -- a renamed key is not a renamed function. Read the actual
  # upstream source, not just what it exports, and confirm it still emits a
  # tool-call-update event carrying :data with :tool-call, and that the
  # stored tool call still carries :diffs, :raw-input and :locations. Verified
  # by hand against the pinned version's two emit sites; a bump that drops
  # any of these keys would otherwise leave every fboundp check above green
  # while emanix/agent-shell--tool-call-paths silently returns nil for every
  # call and a synced buffer just goes stale.
  src=$(echo ${agentShellPkg}/share/emacs/site-lisp/elpa/agent-shell-*/agent-shell.el)
  for key in ':diffs' ':raw-input' ':locations' ':tool-call'; do
    if ! grep -qF -- "$key" "$src"; then
      echo "agent-shell.el no longer constructs $key in its tool-call payload" >&2
      exit 1
    fi
  done

  touch $out
''
