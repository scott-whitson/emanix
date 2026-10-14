# The welcome buffer is the first thing a new user reads, so a key it
# advertises that does not exist is worse than no buffer at all.
#
# This guards the failure that actually happened to the docs: emanix.net
# published `elisa' for weeks after arc replaced it. Nothing detected it
# because nothing compared what the docs claimed against what the code did.
#
# It does NOT generate the buffer from the bindings, and deliberately so. Two
# thirds of the documented super-key surface is EWM upstream's keymap in the
# ewm input, not in this repo; fallback.el is a second, intentional definition
# site; and the manual's rows aggregate many bindings each while its prose
# explains rather than lists. Generation would have to discard all of that.
# Checking is cheap and loses nothing.
{ pkgs, ... }:
pkgs.runCommand "emanix-welcome-keys" { } ''
  welcome=${../emacs/lisp/emanix-welcome.el}
  config=${../emacs/config.el}
  fallback=${../emacs/fallback.el}
  arc=${../emacs/lisp/emanix-arc.el}

  # 1. No absolute home path. Same rule as arc-glue.nix, same reason.
  if grep -nE '"/home/[a-z]' "$welcome"; then
    echo "emanix-welcome.el contains an absolute home path; derive it from \$HOME" >&2
    exit 1
  fi

  # 2. The pre-rename name must not reappear.
  if grep -n 'eminix' "$welcome"; then
    echo "emanix-welcome.el mentions the pre-rename distro name; it is emanix now" >&2
    exit 1
  fi

  # 3. Every C-* key the buffer advertises must be bound by a LIVE binding form
  #    in the shipped elisp. EWM's own super-keys are not checked: they live in
  #    the ewm input, which this repo cannot see.
  #
  #    The extraction pattern reaches a lowercase prefix plus one
  #    lowercase-or-`?' token and no further — a digit, an uppercase letter or a
  #    chord like `C-c C-i' is not extracted and will not be seen. Widen it, and
  #    re-run the fail/pass drill, before trusting it on such a row.
  #
  #    KNOWN RESIDUAL GAP: a real code line whose own trailing comment contains a
  #    complete binding shape still matches, because grep cannot tell where a
  #    line's code ends and its comment begins. Nothing in this tree does that
  #    today; closing it needs parsing, not grep.
  #
  #    The four traps found while writing this — the brief's regex, the
  #    word-splitting loop, substring membership, and a commented-out binding —
  #    are in docs/decisions/welcome-keys-check.md.
  keys=$(grep -oE 'C-[a-z] [a-z?]' "$welcome" | sort -u)

  # An empty extraction is a guard that has stopped seeing its subject, not a
  # clean bill of health -- if the buffer's render format ever changes so
  # this pattern matches nothing, the loop below must not be allowed to pass
  # by iterating zero times.
  if [ -z "$keys" ]; then
    echo "emanix-welcome.el: no C-* keys were extracted from the buffer text; the extraction pattern no longer matches this file's format" >&2
    exit 1
  fi

  fails=0
  # Emacs's own default bindings are exempt: the buffer legitimately points at
  # built-ins, and emanix does not bind these and never should, so demanding a
  # binding form for them would fail on correct code. Deliberately tiny, and NOT
  # an escape hatch — see docs/decisions/welcome-keys-check.md.
  builtin_key() {
    case "$1" in
    "C-h i" | "C-h b" | "C-h k" | "C-h f" | "C-h v" | "C-h m") return 0 ;;
    *) return 1 ;;
    esac
  }

  while IFS= read -r key; do
    [ -n "$key" ] || continue
    if builtin_key "$key"; then continue; fi
    bound=0
    for src in "$config" "$fallback" "$arc"; do
      if grep -vE '^[[:space:]]*;' "$src" \
         | grep -qE '(global-set-key|keymap-global-set|keymap-set|define-key|bind-key)[^"]*"'"$key"'"'; then
        bound=1
        break
      fi
    done
    if [ "$bound" -eq 0 ]; then
      echo "emanix-welcome.el advertises '$key' but no live binding form in config.el, fallback.el, or emanix-arc.el sets it" >&2
      fails=1
    fi
  done <<< "$keys"
  [ "$fails" -eq 0 ] || exit 1

  # 4. The buffer must still name the site. It is the only manual there is, and
  #    a welcome buffer that does not point at it orphans the reader.
  if ! grep -q 'emanix.net' "$welcome"; then
    echo "emanix-welcome.el no longer points at emanix.net" >&2
    exit 1
  fi

  # 5. The runtime probes must still be there. Replace either with a constant
  #    and the buffer starts telling a stranger about a path they do not have.
  for required in emanix-welcome--config-repo emanix-welcome--dismissed-file; do
    if ! grep -q "$required" "$welcome"; then
      echo "emanix-welcome.el no longer defines $required" >&2
      exit 1
    fi
  done

  touch $out
''
