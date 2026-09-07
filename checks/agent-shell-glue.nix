# Modelled on checks/arc-glue.nix: cheap greps over one file, run on every
# `nix flake check' rather than whenever someone remembers to look.
#
# Each grep guards a failure that is SILENT in practice. A missing autoload
# gives you a keybinding that reports a void function only when you press it.
# A top-level `require' of agent-shell would break checks/agent-shell-sync.nix,
# but only there, so it would look fine on a real host. And the two mixed key
# styles in the tool-call payload fail by matching nothing at all.
{ pkgs, ... }:
pkgs.runCommand "agent-shell-glue-sane" { } ''
  src=${../ioshi/i-intelligence/emacs/lisp/emanix-agent-shell.el}

  # 1. No absolute home path, ever. The distro cannot know the operator's name.
  if grep -nE '"/home/[a-z]' "$src"; then
    echo "emanix-agent-shell.el contains an absolute home path" >&2
    exit 1
  fi

  # 2. No top-level require of agent-shell. It must stay loadable under the
  #    bare batch Emacs that runs the unit tests.
  if grep -nE '^\(require .agent-shell' "$src"; then
    echo "emanix-agent-shell.el requires agent-shell at top level; use with-eval-after-load" >&2
    exit 1
  fi

  # 3. The adapter is found on PATH, never hardcoded to a store path: config.el
  #    is out-of-store live elisp and cannot interpolate nix.
  if grep -nE '"/nix/store' "$src"; then
    echo "emanix-agent-shell.el hardcodes a store path" >&2
    exit 1
  fi

  # 4. Both key styles must still be read. Drop either and the sync silently
  #    stops finding files.
  for required in ':raw-input' ':locations' ':diffs' "'path"; do
    if ! grep -qF -- "$required" "$src"; then
      echo "emanix-agent-shell.el no longer reads $required from the tool call" >&2
      exit 1
    fi
  done

  # 5. The three commands the keybindings name must be autoloaded.
  for cmd in \
    agent-shell-anthropic-start-claude-code \
    agent-shell-pi-start-agent \
    agent-shell-send-region
  do
    if ! grep -q "autoload '$cmd" "$src"; then
      echo "emanix-agent-shell.el does not autoload $cmd" >&2
      exit 1
    fi
  done

  touch $out
''
