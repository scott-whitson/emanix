# Guards the defect that motivated arc: the distro cannot know the operator's
# username, so a hardcoded /home/<user> path in shipped elisp silently indexes
# nothing while the assistant keeps answering from the Emacs manuals and looks
# perfectly healthy doing it. That is exactly how the previous assistant ran
# for six weeks.
#
# Cheap on purpose: three greps over one file, no Emacs closure. It runs on
# every `nix flake check' rather than only when someone remembers to look.
{ pkgs, ... }:
pkgs.runCommand "arc-glue-sane" { } ''
  src=${../emacs/lisp/emanix-arc.el}

  # 1. No absolute home path, ever. Derive from $HOME.
  if grep -nE '"/home/[a-z]' "$src"; then
    echo "emanix-arc.el contains an absolute home path; derive it from \$HOME" >&2
    exit 1
  fi

  # 2. The distro is emanix. arc's own upstream defaults still carry the
  #    pre-rename name and point at a projects directory that exists on no
  #    host here, which is precisely why this file overrides them. The old
  #    name reappearing means that override has drifted back.
  if grep -n 'eminix' "$src"; then
    echo "emanix-arc.el mentions the pre-rename distro name; it is emanix now" >&2
    exit 1
  fi

  # 3. The overrides must still be there. Drop one and arc quietly inherits a
  #    default pointing at a directory that does not exist -- no error, no
  #    warning, an empty collection, and an oracle that sounds fine.
  for required in \
    arc-collection-directory-alist \
    arc-index-plan \
    arc-enabled-collections \
    arc-ui-capture-function
  do
    if ! grep -q "$required" "$src"; then
      echo "emanix-arc.el no longer sets $required" >&2
      exit 1
    fi
  done

  # 4. The distro owns the ARC key contract. The old package's command map
  # disappears with the prose-answer layer, so Emanix must bind its own map
  # and own the retrieval wrapper while retaining the pinned-package fallback.
  for required in \
    emanix/arc-search \
    emanix/arc-search-vault \
    emanix/arc-search-options \
    emanix/arc-command-map
  do
    if ! grep -qF "$required" "$src"; then
      echo "emanix-arc.el no longer defines $required" >&2
      exit 1
    fi
  done
  if grep -qF '(keymap-set global-map "C-c i" arc-command-map)' "$src"; then
    echo "emanix-arc.el binds ARC's internal command map directly" >&2
    exit 1
  fi
  if ! grep -qF "(require 'arc-search-ui nil :no-error)" "$src"; then
    echo "emanix-arc.el no longer keeps the newer search UI optional" >&2
    exit 1
  fi

  touch $out
''
