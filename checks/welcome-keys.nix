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
  welcome=${../ioshi/i-intelligence/emacs/lisp/emanix-welcome.el}
  config=${../ioshi/i-intelligence/emacs/config.el}
  fallback=${../ioshi/i-intelligence/emacs/fallback.el}
  arc=${../ioshi/i-intelligence/emacs/lisp/emanix-arc.el}

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

  # 3. Every Emacs binding the buffer advertises must be bound somewhere in the
  #    shipped elisp. EWM's own super-keys are NOT checked here -- they live in
  #    the ewm input and this repo cannot see them -- so only C-* claims are
  #    verified, which is exactly the set this repo is responsible for.
  #
  #    The brief this check was written from used a narrower extraction
  #    regex, requiring either surrounding double quotes or a `C-c' prefix.
  #    Neither branch matches the buffer's own `C-x g' row, so it would never
  #    have been checked. This pattern matches any `C-<letter> <char>' pair
  #    regardless of quoting or prefix letter.
  #
  #    `C-c i' is genuinely bound, but only in emanix-arc.el (guarded behind
  #    `(featurep 'arc)'), not in config.el or fallback.el -- so arc.el is
  #    checked too, alongside the two files the brief named.
  #
  #    The brief's loop was `for key in $(... | sort -u)': unquoted command
  #    substitution word-splits on whitespace, so a two-token key like
  #    "C-c i" arrives as two separate words, "C-c" and "i". Both are
  #    near-universal substrings of any real elisp file (a lone letter like
  #    `i' or `j' matches almost anywhere), so that form of the loop passes
  #    no matter what the buffer advertises -- verified: it let a deliberately
  #    wrong "C-c j" through. Reading keys line-by-line keeps each one whole.
  fails=0
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    if ! grep -qF "$key" "$config" && ! grep -qF "$key" "$fallback" \
       && ! grep -qF "$key" "$arc"; then
      echo "emanix-welcome.el advertises '$key' but nothing in config.el, fallback.el, or emanix-arc.el binds it" >&2
      fails=1
    fi
  done < <(grep -oE 'C-[a-z] [a-z?]' "$welcome" | sort -u)
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
