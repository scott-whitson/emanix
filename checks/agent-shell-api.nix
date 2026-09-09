# The upstream API this integration is built on, asserted against the package
# the hosts actually run.
#
# `pkgs' HERE IS NOT THE FLAKE'S `pkgs'. flake.nix binds that to bare
# nixpkgs.legacyPackages and applies the emacs-overlay only inside a NixOS
# module, which `checks' never evaluates -- so for its first life this check
# silently asserted against nixpkgs' own agent-shell (20260807.941) while every
# emanix host ran the overlay's (20260901.930). flake.nix now passes
# `pkgs.extend emacs-overlay.overlays.default' to THIS check specifically; if
# that ever reverts to a plain `inherit pkgs', the guard goes back to
# describing a version nobody runs.
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
                         agent-shell-pi-start-agent
                         agent-shell-cwd)))
      (unless (fboundp sym)
        (error "agent-shell no longer defines %s" sym)))
    (dolist (var (quote (agent-shell-mode-hook
                         agent-shell-anthropic-claude-acp-command
                         agent-shell-pi-acp-command
                         agent-shell-text-file-capabilities)))
      (unless (boundp var)
        (error "agent-shell no longer defines %s" var)))
    ;; The event name the buffer-sync patch subscribes to. Documented only in
    ;; the docstring of agent-shell-subscribe-to, so assert against that.
    (unless (string-match-p "tool-call-update"
                            (documentation (quote agent-shell-subscribe-to)))
      (error "agent-shell no longer documents the tool-call-update event")))'

  # The symbols above can all stay green while the payload SHAPE underneath
  # them changes -- a renamed key is not a renamed function. So read the actual
  # upstream source and confirm it still CONSTRUCTS the keys
  # emanix/agent-shell--tool-call-paths reads.
  #
  # Anchored to the construction sites, not to the bare keywords. The bare
  # keywords could not fail: in the pinned source `:tool-call' appears 64
  # times, 17 of them as `:tool-call-id', and the rest overwhelmingly in
  # rendering and transcript code -- so `grep -F :tool-call' stayed green no
  # matter what happened to the emitted payload. `(cons :tool-call ' (note the
  # trailing space) matches the four real construction sites and excludes
  # `:tool-call-id' by construction.
  src=$(echo ${agentShellPkg}/share/emacs/site-lisp/elpa/agent-shell-*/agent-shell.el)
  for form in \
    "(cons :tool-call " \
    "(cons :diffs " \
    "(cons :locations " \
    "(cons :raw-input " \
    "(cons :file "
  do
    if ! grep -qF -- "$form" "$src"; then
      echo "agent-shell.el no longer builds its tool-call payload with $form" >&2
      exit 1
    fi
  done

  # emanix/agent-shell-claude opens an agent on another tree by binding
  # `default-directory' around the upstream command, and that is the ENTIRE
  # mechanism -- it works only while `agent-shell-cwd' still reads
  # `default-directory'. If upstream ever resolves the cwd some other way (a
  # stored variable, a required argument), the wrapper keeps running, the
  # prompt keeps appearing, and the shell quietly starts in the wrong
  # directory: no error, and the C-u branch silently becomes a no-op.
  # `fboundp agent-shell-cwd' above cannot see that; this reads the body.
  #
  # Scoped to the defun rather than grepping the whole file, because
  # `default-directory' appears all over agent-shell-project.el. "End of form"
  # is the next line starting a top-level form in column 0; an awk RANGE
  # ending at /^$/ was tried first and is WRONG -- the blank line inside this
  # defun's own docstring closes it after three lines, so the guard failed red
  # against correct source. Docstring and body lines are indented or blank, so
  # only a real following form can stop it. Drilled three ways: green as
  # shipped, red when the fallback is replaced, red when the defun is renamed.
  proj=$(echo ${agentShellPkg}/share/emacs/site-lisp/elpa/agent-shell-*/agent-shell-project.el)
  if ! awk '/^\(defun agent-shell-cwd /{f=1;print;next} f&&/^\(/{exit} f{print}' "$proj" \
       | grep -qF default-directory; then
    echo "agent-shell-cwd no longer resolves the cwd from default-directory; emanix/agent-shell-claude's C-u branch is silently broken" >&2
    exit 1
  fi

  # Two emit sites, and the sync patch depends on BOTH. They carry overlapping
  # subsets of these keys rather than disjoint ones. Losing one would halve the
  # paths the sync sees while every presence grep above stayed green, so count
  # rather than merely match.
  emits=$(grep -cF -- ":event 'tool-call-update" "$src")
  if [ "$emits" -ne 2 ]; then
    echo "agent-shell.el emits tool-call-update from $emits sites, expected 2" >&2
    exit 1
  fi

  touch $out
''
