# The upstream API this integration is built on, asserted against the package
# the overlay actually pins.
#
# agent-shell's author describes the API as unstable and acp.el as not yet
# API-stable, and emanix-agent-shell.el reads an undocumented event payload.
# A bump that renames `agent-shell-subscribe-to' or drops agent-shell-pi would
# otherwise surface as a keybinding that errors when pressed, weeks later.
{ pkgs, ... }:
let
  emacsWithAgentShell =
    (pkgs.emacsPackagesFor pkgs.emacs-nox).emacsWithPackages
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
  touch $out
''
