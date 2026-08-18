#!/usr/bin/env python3
"""Assert every accent slot clears WCAG AAA (7:1) against its palette base.

Usage:
  nix eval --json --impure --expr \
    '(import ./lib/themes.nix { pkgs = import <nixpkgs> {}; }).palettes' \
    | python3 tests/contrast-check.py
"""
import json, sys

ACCENTS = ["rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach",
           "yellow", "green", "teal", "sky", "sapphire", "blue", "lavender",
           "text", "subtext1", "subtext0", "overlay0"]
MIN = 7.0

def luminance(h):
    h = h.lstrip("#")
    ch = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    ch = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in ch]
    return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]

def ratio(a, b):
    hi, lo = sorted([luminance(a), luminance(b)], reverse=True)
    return (hi + 0.05) / (lo + 0.05)

def main():
    palettes = json.load(sys.stdin)
    failures = []
    for name, p in sorted(palettes.items()):
        if not name.startswith("high-contrast-"):
            continue          # catppuccin is knowingly below AAA; see the spec
        base = p["colors"]["base"]
        for slot in ACCENTS:
            r = ratio(p["colors"][slot], base)
            if r < MIN:
                failures.append(f"{name}.{slot}: {r:.2f}:1 (need {MIN})")
        worst = min(ratio(p["colors"][s], base) for s in ACCENTS)
        print(f"{name}: text/base={ratio(p['colors']['text'], base):.2f}:1  "
              f"lowest accent={worst:.2f}:1")
    if failures:
        print("\nFAILURES:", file=sys.stderr)
        for f in failures:
            print("  " + f, file=sys.stderr)
        sys.exit(1)
    print("\nAll high-contrast accents clear AAA.")

main()
