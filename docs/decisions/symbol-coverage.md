# Font symbol coverage: the two halves, and why the rule sits on a frame hook

**Applies to** the symbol-fontset block in `emacs/config.el`. **Decided**
2026-09-02, from the measurement below. **Relocated** here on 2026-11-02, when
the rationale moved out of the comment to fit the 30-line budget.

## Decision

Wire the Private Use Areas to Symbols Nerd Font Mono explicitly, from the frame
hooks rather than once at load.

## The two halves fail differently

**TUI symbols** (Claude Code's ⏵ ⏸ ⏺ ✻ ✦) are ordinary Unicode, and fontconfig
fallback finds them in `pkgs.noto-fonts` on its own — verified: U+23F5 resolves
to Noto Sans Symbols 2 with nothing configured.

**ICON glyphs do not fall back.** The top bar draws battery, volume and network
from Nerd Font's Material Design set at U+F0000–U+FFFFD, and Emacs's fontconfig
fallback does not reach the Private Use Areas: with the ranges removed, U+F0079
resolves to NO font at all while U+23F5 resolves fine. So the PUA ranges must be
wired explicitly.

Mono variant deliberately: the proportional "Symbols Nerd Font" breaks the
character grid in a monospace top bar.

## It is a timing bug, not an inert call

This corrects a claim that used to sit in the comment — that `set-fontset-font`
is inert on this pgtk/ftcrhb build. It is not. That was measured against the
media-control block, where fallback already supplied a font, so forcing another
family changed nothing *visible*. The genuine finding about those characters is
about ADVANCE WIDTH, not coverage: no font draws them at the 9px cell, which no
amount of font selection fixes. That is still true, and is why the display table
further down in `config.el` exists.

## The measurement

2026-09-02, on the EWM reference host, after a rebuild and reboot: U+F0079 gave
`internal-char-font' => NO FONT and `fontset-font' => (nil . gb18030*-*), while
re-evaluating the IDENTICAL `set-fontset-font` calls in that same live session
resolved it to "Symbols Nerd Font Mono" immediately. The rule was never wrong;
its timing was. Symptom: the top bar's battery and volume glyphs render as empty
boxes after every restart.

## Why the frame hooks

This is a DAEMON. At startup there is no frame; when one is created, the default
face's family (set above) is realized into a fresh fontset that does NOT carry
these prepends, so a rule applied at load time reaches nothing.

The calls are idempotent, so every call after the first is a no-op.
