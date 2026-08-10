# High Contrast Dark

Maximum-legibility dark theme. Variant: **dark**.

Base `#0a0a0a`, text `#e8e8e8` — **16.16:1**, against Catppuccin Mocha's
11.34:1. Every accent slot clears WCAG AAA (7:1) against the base; the lowest
is `overlay0` at 7.12:1, where Mocha sits at 3.36:1.

Deliberately **not** `#000`/`#fff` (21:1). Pure white on pure black causes
halation — text appearing to glow or smear — which is commonly worse for
visual snow than a slightly softened pair.

Generated from `lib/themes.nix` by `bin/gen-theme-dir.py`. Do not hand-edit;
change the palette and re-run, then re-run `tests/contrast-check.py`.
