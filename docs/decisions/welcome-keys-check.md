# What `checks/welcome-keys.nix` checks, and how far the pattern reaches

**Applies to** `checks/welcome-keys.nix`. **Decided** 2026-10-14, when the
rationale moved out of the check to keep its comment inside the 30-line budget.

## Decision

The check verifies that every `C-*` key the welcome buffer advertises is bound
by a **live binding form** in the shipped elisp, and it does not generate the
buffer from the bindings.

## Why not generation

Two thirds of the documented super-key surface is EWM upstream's keymap, in the
`ewm` input rather than this repo. `fallback.el` is a second, intentional
definition site. The manual's rows aggregate many bindings each while its prose
explains rather than lists. Generation would have to discard all of that.
Checking is cheap and loses nothing.

## The extraction pattern, and what it cannot see

`grep -oE 'C-[a-z] [a-z?]'` over the buffer text. It extracts a single lowercase
prefix key followed by exactly one lowercase-or-`?` second token.

**Reach:** a future row using a digit, an uppercase letter, or a chord like
`C-c C-i` will not be extracted at all, and the guard will not see it. Widen the
pattern — and re-run the fail/pass drill — before trusting it on such a row.

`C-c i` is genuinely bound, but only in `emanix-arc.el` (behind
`(featurep 'arc)`), not in `config.el` or `fallback.el`, so `arc.el` is checked
too.

An empty extraction is treated as a failure, not a pass: if the buffer's render
format changes so the pattern matches nothing, the loop below must not be allowed
to succeed by iterating zero times.

## Four traps found while writing it

1. **The brief's regex** required surrounding double quotes or a `C-c` prefix.
   Neither branch matches the buffer's own `C-x g` row, so that row would never
   have been checked.
2. **Unquoted command substitution word-splits.** The brief's
   `for key in $(... | sort -u)` delivered a two-token key like `C-c i` as two
   words, `C-c` and `i`. Both are near-universal substrings of any real elisp
   file, so that loop passed no matter what the buffer advertised — verified: it
   let a deliberately wrong `C-c j` through. Reading keys line-by-line keeps each
   one whole.
3. **Substring membership was too weak.** `grep -qF "$key"` matches the key
   anywhere in the file, including comment prose that mentions a key without
   binding it — `config.el` has "C-u C-c t = new terminal" and "C-c z toggles
   back to raw monospace". Deleting the real binding left such a comment behind
   and the check kept passing. A key must now appear inside an actual binding
   call.
4. **A commented-out binding satisfied it.** The pattern has no start-of-line
   anchor, so `;; (global-set-key (kbd "C-c t") #'ghostel)` still matched.
   Commenting a binding out is the likeliest way one disappears, more likely than
   deleting the line, so lines whose first non-blank character is `;` are dropped
   before matching.

## Known residual gap, left deliberately

A real code line whose *own trailing comment* contains a complete binding shape
— `(setq x t) ;; (global-set-key (kbd "C-c t") ...)` — still matches, because
the grep pattern has no notion of where a line's code ends and its comment
begins. Nothing in the tree does this today. Narrowing further needs parsing, not
grep; that is the point at which this stops being cheap.

## The built-in exemption

`C-h i`, `C-h b`, `C-h k`, `C-h f`, `C-h v`, `C-h m` are exempt because stock
Emacs binds them with no configuration, and the buffer legitimately points at
them — a guide that cannot name `C-h i` is not a guide. It is deliberately tiny
and is not an escape hatch: a key belongs there only if stock Emacs binds it.
Anything emanix itself provides must still prove a live binding form. A future
entry being tempting to add is the signal that it ought to be bound instead.
