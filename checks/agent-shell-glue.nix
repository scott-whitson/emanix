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
  src=${../emacs/lisp/emanix-agent-shell.el}

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

  # 4. Every branch of the path extractor must still be READ, not merely
  #    mentioned.
  #
  #    This used to grep for the bare keywords ':raw-input', ':locations',
  #    ':diffs', ':content'. Three of those four could not fail: the function's
  #    own docstring names `:locations', `:raw-input' and `:diffs' in prose, so
  #    deleting the entire `(dolist (d (map-elt tool-call :diffs)) ...)' form
  #    left this check green. Grep for the CODE FORM instead -- prose cannot
  #    satisfy `(map-elt tool-call :diffs)'. And `:file', the key actually read
  #    out of each diff, was guarded by nothing at all; it is guarded now.
  #
  #    These are the literal forms in emanix/agent-shell--tool-call-paths. If
  #    that function is legitimately refactored (renamed locals, a different
  #    accessor), update the strings here deliberately -- do not delete them.
  for form in \
    "(map-elt tool-call :diffs)" \
    "(map-elt tool-call :locations)" \
    "(map-elt tool-call :content)" \
    "(:raw-input file_path)" \
    "(map-elt d :file)"
  do
    if ! grep -qF -- "$form" "$src"; then
      echo "emanix-agent-shell.el no longer reads the tool call via $form" >&2
      exit 1
    fi
  done

  # 4b. 'path is read from TWO separate branches (:locations and :content),
  #     each a vector of symbol-keyed alists. A presence-only grep cannot
  #     distinguish one branch from two, so deleting the :content branch
  #     outright would still satisfy every string above -- the check would
  #     pass while the regression shipped. Count the occurrences instead.
  #
  #     Counted over comment-stripped source, for the same reason as 4: the
  #     docstring above the function is free to discuss 'path, and a count that
  #     prose can inflate is a count that cannot fail. sed drops everything from
  #     the first `;' on each line, which is a safety measure rather than an exact
  #     elisp tokeniser -- the module does contain a `;' inside a docstring, so a
  #     line can be truncated early. Stripping can therefore only ever UNDERCOUNT,
  #     which fails RED and never GREEN: the direction a guard may be wrong in.
  path_count=$(sed 's/;.*//' "$src" | grep -oF "'path" | wc -l)
  if [ "$path_count" -lt 2 ]; then
    echo "emanix-agent-shell.el reads 'path in fewer than 2 code branches (found $path_count); the :locations and :content branches must each read it" >&2
    exit 1
  fi

  # 4c. The Claude wrapper C-c C-' is bound to. config.el names
  #     `emanix/agent-shell-claude' and this module is the only definition
  #     site, so losing it costs the primary agent keybinding -- and does so
  #     silently, because config.el requires this feature with :no-error.
  #
  #     `defun' specifically, not merely the symbol: the docstring and
  #     config.el's own comment both name it, so a presence grep would survive
  #     the function being deleted. The wrapper's BEHAVIOUR (that it honours
  #     the prompted directory) is unit-tested in checks/agent-shell-sync.nix
  #     instead, where a batch Emacs can actually call it.
  if ! grep -qF -- "(defun emanix/agent-shell-claude " "$src"; then
    echo "emanix-agent-shell.el no longer defines emanix/agent-shell-claude, which config.el binds to C-c C-'" >&2
    exit 1
  fi

  # 4d. The sleep-inhibit latch must still be INSTALLED, not merely defined.
  #     checks/agent-shell-sync.nix unit-tests the function, and would keep
  #     passing with the `advice-add' deleted -- the tests call it directly.
  #     Losing the installation is silent by nature: the only symptom is the
  #     echo-area message storm coming back on hosts where logind refuses to
  #     inhibit, which no check can observe from a build sandbox.
  if ! grep -q "advice-add 'system-sleep-block-sleep" "$src"; then
    echo "emanix-agent-shell.el no longer installs emanix/agent-shell--sleep-block-latch on system-sleep-block-sleep" >&2
    exit 1
  fi

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
