# High Contrast Light

Maximum-legibility light theme. Variant: **light**.

Base `#f2f2f2`, text `#111111` — **16.87:1**, against Catppuccin Latte's
7.06:1. Every accent slot clears WCAG AAA (7:1) against the base; the lowest
is `red` at 7.06:1. Latte fails AA outright in three of four sampled pairs
(`overlay0` 2.30:1, `subtext0` 4.37:1, `blue` 4.34:1), which is what this
theme exists to fix.

Base is off-white rather than `#ffffff` on purpose: a large pure-white surface
is a common photophobia trigger.

Generated from `lib/themes.nix` by `bin/gen-theme-dir.py`. Do not hand-edit;
change the palette and re-run, then re-run `tests/contrast-check.py`.
