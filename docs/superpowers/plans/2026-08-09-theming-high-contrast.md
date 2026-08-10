# eminix Theming — High-Contrast Variants Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Tasks 1–8 are agent-executable repo work.** Task 9 is operational — it must
> be run by Scott on rafik because it needs a live EWM session and `sudo`.

**Goal:** Add a high-contrast dark/light pair to the eminix theme system and extend that system to cover Emacs beyond Catppuccin, Firefox chrome, zellij, and Claude Code.

**Architecture:** `lib/themes.nix` holds the palettes and is the single source of truth. Nix pre-renders every theme for every app at build time; `bin/dot-theme-set` selects among them at runtime by flipping symlinks and notifying running processes. The switcher never generates config and never writes inside the checkout.

**Tech Stack:** Nix + Home Manager, Emacs 30.2 (Modus themes, built in), ghostty, zellij 0.44.3, Firefox `userChrome.css`, Claude Code settings.

**Spec:** `docs/superpowers/specs/2026-08-09-theming-high-contrast-design.md`. Read its Decisions section before starting.

## Global Constraints

- **Never add `Co-Authored-By` or tool-attribution trailers to commits.**
- All `.nix` files must pass `nixpkgs-fmt --check` before commit.
- Build check (used throughout): `for h in rafik whistle datacore; do nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel; done`
- **`datacore` and `whistle` closures must not change** except where a task genuinely adds a file they consume. Check before/after; an unexplained change means something leaked into the wrong host.
- **Nothing may write inside `~/dotfiles` at theme-switch time.** After any `dot-theme-set` run, `git status --porcelain` must be empty. This is the "Helix drift caveat" in `docs/manual/02-theming.md`.
- Every accent slot in both new palettes must measure **≥7:1 against its own base**. The contrast test in Task 1 enforces this.
- **`~/.claude/settings.json` is the single documented exception** to the no-writes rule — `claude.nix` already accepts a dirty tree for it.

## File Structure

| File | Responsibility |
|---|---|
| `lib/themes.nix` | **Modify.** Palettes (now 4), `ansiSlots` (variant-aware ANSI order), config generators. Single source of truth for colour AND for ANSI slot order. |
| `bin/gen-theme-dir.py` | **Create.** Renders `themes/<name>/` from a palette. Run at authoring time, output committed. |
| `themes/high-contrast-{dark,light}/` | **Create.** Runtime theme directories. |
| `themes/*/emacs-theme` | **Create** (all 4). Names the Emacs theme to load. |
| `themes/*/ghostty.conf` | **Delete** (all 4). Superseded by Nix-rendered variants. |
| `bin/gen-pi-theme.py` | **Modify.** Accept a `[palette]` section, not only `[catppuccin]`. |
| `bin/dot-theme-set` | **Modify.** Fix emacsclient path; pass theme *name*; ghostty source dir; zellij + Claude state. |
| `ioshi/i-intelligence/ghostty.nix` | **Modify.** Stop owning `theme.conf`; pre-render 4 variants; seed on activation. |
| `ioshi/i-intelligence/emacs/lisp/scott-theme.el` | **Rewrite.** Name-based, Modus overrides. |
| `ioshi/i-intelligence/firefox.nix` | **Modify.** Per-theme `userChrome.css`. |
| `ioshi/i-intelligence/zellij/config.kdl` | **Modify.** `theme_dir` + `theme "active"` + two ANSI themes. |
| `ioshi/i-intelligence/claude/settings.json` | **Modify.** Add `theme` key. |
| `docs/manual/02-theming.md` | **Modify.** Four themes; new anatomy; Firefox off the omissions list. |

---

## Task 1: Palettes and generator cleanup in `lib/themes.nix`

**Agent-executable.**

**Files:**
- Modify: `lib/themes.nix`
- Create: `tests/contrast-check.py`

**Interfaces:**
- Produces: `palettes.high-contrast-dark` and `palettes.high-contrast-light`, each a `{ variant, colors }` attrset with the same 26 colour slots as the Catppuccin palettes. Every later task reads these by slot name.

**Why the dead generators go:** `hyprland` and `mako` generators are still defined, but `hyprland.nix`, `mako.nix` and `fuzzel.nix` were deleted in the 2026-08-07 convergence. Nothing calls them.

- [ ] **Step 1: Write the contrast test**

Create `tests/contrast-check.py`:

```python
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
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd ~/dotfiles
nix eval --json --impure --expr '(import ./lib/themes.nix { pkgs = import <nixpkgs> {}; }).palettes' \
  | python3 tests/contrast-check.py
```

Expected: prints nothing for high-contrast (no such palettes yet) and reports "All high-contrast accents clear AAA." vacuously. **That vacuous pass is the failure** — it proves the palettes are absent. Confirm with:

```bash
nix eval --json --impure --expr '(import ./lib/themes.nix { pkgs = import <nixpkgs> {}; }).palettes' \
  | python3 -c 'import json,sys; print(sorted(json.load(sys.stdin)))'
```

Expected: `['catppuccin-latte', 'catppuccin-mocha']`

- [ ] **Step 3: Add the two palettes**

In `lib/themes.nix`, inside `palettes = { ... }` after `catppuccin-latte`, add:

```nix
    # High-contrast pair. Driven by an accessibility need (visual snow
    # syndrome), not aesthetics — see the 2026-08-09 spec. Deliberately NOT
    # 21:1: pure #fff on #000 causes halation, which is commonly worse than a
    # softened pair, and a pure-white background is a photophobia trigger.
    # Every accent below clears 7:1 against its own base; tests/contrast-check.py
    # enforces that. Do not "tidy" these values without re-running it.
    high-contrast-dark = {
      variant = "dark";
      colors = {
        rosewater = "#ffd7d0";
        flamingo = "#ffb3a7";
        pink = "#ff9ee0";
        mauve = "#c9a3ff";
        red = "#ff6b6b";
        maroon = "#ff8f8f";
        peach = "#ffb060";
        yellow = "#ffd93d";
        green = "#5ee06a";
        teal = "#4fe0c8";
        sky = "#5fd7ff";
        sapphire = "#4cc8f0";
        blue = "#7ab8ff";
        lavender = "#b9c4ff";
        text = "#e8e8e8";
        subtext1 = "#dcdcdc";
        subtext0 = "#cfcfcf";
        overlay2 = "#b2b2b2";
        overlay1 = "#9e9e9e";
        overlay0 = "#9b9b9b";
        surface2 = "#3d3d3d";
        surface1 = "#2e2e2e";
        surface0 = "#1f1f1f";
        base = "#0a0a0a";
        mantle = "#050505";
        crust = "#000000";
      };
    };

    high-contrast-light = {
      variant = "light";
      colors = {
        rosewater = "#8a3324";
        flamingo = "#95291e";
        pink = "#9d006b";
        mauve = "#6b21a8";
        red = "#a70019";
        maroon = "#96001a";
        peach = "#804000";
        yellow = "#654d00";
        green = "#0d5e1b";
        teal = "#005a56";
        sky = "#005776";
        sapphire = "#00567a";
        blue = "#0043a8";
        lavender = "#3b3ba8";
        text = "#111111";
        subtext1 = "#212121";
        subtext0 = "#2e2e2e";
        overlay2 = "#3a3a3a";
        overlay1 = "#4a4a4a";
        overlay0 = "#515151";
        surface2 = "#b0b0b0";
        surface1 = "#c4c4c4";
        surface0 = "#d6d6d6";
        base = "#f2f2f2";
        mantle = "#e8e8e8";
        crust = "#dedede";
      };
    };
```

- [ ] **Step 4: Delete the dead generators**

Remove the whole `hyprland = palette: ''...'';` block and the whole
`mako = palette: ''...'';` block. Then remove their two lines from `mkTheme`:

```nix
  mkTheme = palette: {
    ghostty = ghostty palette;
    swaylock = swaylock palette;
    variant = palette.variant;
    colors = palette.colors;
  };
```

- [ ] **Step 5: Run the contrast test — it must now pass with real output**

```bash
nix eval --json --impure --expr '(import ./lib/themes.nix { pkgs = import <nixpkgs> {}; }).palettes' \
  | python3 tests/contrast-check.py
```

Expected exactly:

```
high-contrast-dark: text/base=16.16:1  lowest accent=7.12:1
high-contrast-light: text/base=16.87:1  lowest accent=7.06:1

All high-contrast accents clear AAA.
```

If any number differs, a palette value was mistyped — fix the value, do not adjust the test.

- [ ] **Step 6: Confirm nothing else broke**

```bash
nixpkgs-fmt --check lib/themes.nix
for h in rafik whistle datacore; do
  printf "%-9s " $h
  nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel
done
grep -rn "lib.theme.hyprland\|lib.theme.mako\|themeLib.hyprland\|themeLib.mako" --include='*.nix' . || echo "no references to deleted generators"
```

- [ ] **Step 7: Commit**

```bash
git add lib/themes.nix tests/contrast-check.py
git commit -m "feat(theme): high-contrast dark/light palettes, drop dead generators

Adds the two palettes the 2026-08-09 spec specifies, at ~16:1 rather than
the available 21:1 — pure white on pure black causes halation, which is
commonly worse for visual snow than a softened pair.

tests/contrast-check.py asserts every accent slot clears 7:1 against its
own base, so a future edit cannot quietly reintroduce a low-contrast value.
Catppuccin is exempt by name: it is knowingly below AAA (latte's overlay0
is 2.30:1) and that is its design, not a defect to fix here.

Also deletes the hyprland and mako generators. Both modules were removed in
the 2026-08-07 convergence and nothing has called these since."
```

---

## Task 1b: Make the ANSI mapping variant-aware

**Agent-executable.** Added 2026-08-10 after Task 2 discovered the defect. Approved by Scott.

**Files:**
- Modify: `lib/themes.nix`

**Interfaces:**
- Produces: `ansiSlots = palette: [ ... 16 slot names ... ]`, exported from `lib/themes.nix`. `bin/gen-theme-dir.py` (Task 2) must emit the same ordering, and Task 6's zellij themes depend on the semantics being right.

**The defect.** `lib/themes.nix`'s `ghostty` generator hardcodes one ANSI order for every palette: `color0 = surface1`, `color7 = subtext0`, `color8 = surface2`, `color15 = subtext1`. On a **light** palette that puts a light colour at index 0 ("black") and a dark colour at index 15 ("white") — inverted. Verified against the committed `themes/catppuccin-latte/colors.toml`, which has it right and therefore disagrees with what `ghostty.nix` renders:

| index | committed Latte | slot | hardcoded order gives | slot |
|---|---|---|---|---|
| `color0` | `#5c5f77` dark | `subtext1` | `#bcc0cc` light | `surface1` |
| `color7` | `#acb0be` | `surface2` | `#6c6f85` | `subtext0` |
| `color8` | `#6c6f85` | `subtext0` | `#acb0be` | `surface2` |
| `color15` | `#bcc0cc` light | `surface1` | `#5c5f77` dark | `subtext1` |

**Why it is load-bearing, not cosmetic:** Task 6's zellij themes use `bg 0`/`fg 7` for dark and `bg 15`/`fg 0` for light, and Task 7's Claude Code `-ansi` themes read the terminal's ANSI palette. An inverted light palette renders both unreadable — the exact opposite of the contrast this project exists to provide.

The light order is the dark order with the greyscale ends exchanged: `0↔15` and `7↔8`.

- [ ] **Step 1: Add the shared ordering and use it in the ghostty generator**

In `lib/themes.nix`, above the `ghostty` generator, add:

```nix
  # ANSI slots 0-15, in order. Light palettes exchange the greyscale ends
  # (0<->15 and 7<->8): index 0 is "black" and 15 is "white", so on a light
  # palette they must be the DARK and LIGHT extremes respectively. The old
  # hardcoded order applied the dark mapping to every palette, which put a
  # light colour at index 0 on latte — inverted, and disagreeing with
  # themes/catppuccin-latte/colors.toml, which had it right.
  #
  # This is not cosmetic: zellij themes and Claude Code's -ansi themes read
  # these indices, so an inverted light palette renders unreadable.
  #
  # bin/gen-theme-dir.py must emit this same ordering.
  ansiSlots = palette:
    let accents = [ "red" "green" "yellow" "blue" "pink" "teal" ];
    in
    if palette.variant == "light"
    then [ "subtext1" ] ++ accents ++ [ "surface2" "subtext0" ] ++ accents ++ [ "surface1" ]
    else [ "surface1" ] ++ accents ++ [ "subtext0" "surface2" ] ++ accents ++ [ "subtext1" ];
```

Then replace the sixteen hardcoded `palette = N=...` lines in the `ghostty` generator with a generated block:

```nix
    ${lib.concatStringsSep "\n" (lib.imap0
      (i: slot: "palette = ${toString i}=${palette.colors.${slot}}")
      (ansiSlots palette))}
```

`lib/themes.nix` currently takes `{ pkgs, ... }`. Change it to `{ pkgs, lib ? pkgs.lib, ... }` so `lib.imap0` and `lib.concatStringsSep` resolve.

Export `ansiSlots` from the returned attrset (it is a `rec`, so simply having the binding is not enough — it must be a top-level attribute, which it already is by virtue of being defined in the `rec { ... }` body).

- [ ] **Step 2: Prove the dark ordering is unchanged and the light one is fixed**

```bash
cd ~/dotfiles
nix eval --json --impure --expr '
  let t = import ./lib/themes.nix { pkgs = import <nixpkgs> {}; };
  in builtins.mapAttrs (n: p: t.ansiSlots p) t.palettes' | python3 -m json.tool
```

Expected: `catppuccin-mocha` and `high-contrast-dark` start `"surface1"` and end `"subtext1"`; `catppuccin-latte` and `high-contrast-light` start `"subtext1"` and end `"surface1"`.

- [ ] **Step 3: Prove the light ordering reproduces the committed Latte values**

This is the real test — the fix is correct if it reproduces a file written by hand before this project existed.

```bash
cd ~/dotfiles
nix eval --json --impure --expr '
  let t = import ./lib/themes.nix { pkgs = import <nixpkgs> {}; };
      p = t.palettes.catppuccin-latte;
  in builtins.listToAttrs (builtins.genList (i: {
       name = "color${toString i}";
       value = p.colors.${builtins.elemAt (t.ansiSlots p) i};
     }) 16)' > /tmp/latte-ansi-generated.json
git show HEAD:themes/catppuccin-latte/colors.toml \
  | sed -n '/^\[ansi\]/,/^$/p' | grep '^color' \
  | python3 -c '
import sys, json, re
d = dict(re.findall(r"(color\d+) = \"(#[0-9a-f]{6})\"", sys.stdin.read()))
print(json.dumps(d, sort_keys=True))' > /tmp/latte-ansi-committed.json
python3 -c '
import json
a = json.load(open("/tmp/latte-ansi-generated.json"))
b = json.load(open("/tmp/latte-ansi-committed.json"))
diff = {k: (a.get(k), b.get(k)) for k in sorted(set(a) | set(b)) if a.get(k) != b.get(k)}
print("IDENTICAL — generated ANSI matches the hand-written committed file" if not diff
      else f"MISMATCH: {diff}")'
```

Expected: `IDENTICAL — generated ANSI matches the hand-written committed file`.

If it mismatches, the ordering is wrong — fix `ansiSlots`, not the committed file.

- [ ] **Step 4: Confirm ghostty output changed only for light palettes**

```bash
cd ~/dotfiles
nixpkgs-fmt --check lib/themes.nix
nix eval --raw --impure --expr '(import ./lib/themes.nix { pkgs = import <nixpkgs> {}; }).ghostty (import ./lib/themes.nix { pkgs = import <nixpkgs> {}; }).palettes.catppuccin-mocha' \
  | grep -E "^palette = (0|7|8|15)="
echo "--- latte ---"
nix eval --raw --impure --expr '(import ./lib/themes.nix { pkgs = import <nixpkgs> {}; }).ghostty (import ./lib/themes.nix { pkgs = import <nixpkgs> {}; }).palettes.catppuccin-latte' \
  | grep -E "^palette = (0|7|8|15)="
```

Expected — mocha unchanged from before this task (`0=#45475a`, `7=#a6adc8`, `8=#585b70`, `15=#bac2de`); latte now `0=#5c5f77`, `7=#acb0be`, `8=#6c6f85`, `15=#bcc0cc`.

- [ ] **Step 5: Build and commit**

```bash
cd ~/dotfiles
for h in rafik whistle datacore; do
  printf "%-9s " $h
  nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel
done
git add lib/themes.nix
git commit -m "fix(theme): ANSI slot order must follow the palette's variant

The ghostty generator hardcoded one ANSI order for every palette, so light
palettes got a light colour at index 0 ('black') and a dark one at index 15
('white') — inverted. themes/catppuccin-latte/colors.toml had it right, which
means ghostty.nix and that file have been disagreeing: two sources of truth
for the same sixteen values, and the Nix one was wrong.

Not cosmetic. zellij themes and Claude Code's -ansi themes read these indices,
so an inverted light palette renders unreadable — the opposite of what the
high-contrast work is for, and it would have shipped in high-contrast-light.

The light order is the dark order with the greyscale ends exchanged (0<->15,
7<->8). Verified by reproduction: generating latte's sixteen values now
matches the hand-written committed file exactly, and mocha's are unchanged."
```

---

## Task 2: Theme-directory generator and the four theme directories

**Agent-executable.**

**Files:**
- Create: `bin/gen-theme-dir.py`
- Create: `themes/high-contrast-dark/{variant,colors.toml,palette.sh,btop.theme,gtk.conf,README.md}`
- Create: `themes/high-contrast-light/{variant,colors.toml,palette.sh,btop.theme,gtk.conf,README.md}`
- Modify: `themes/catppuccin-mocha/colors.toml`, `themes/catppuccin-latte/colors.toml`
- Modify: `bin/gen-pi-theme.py`
- Delete: `themes/*/ghostty.conf` (all four)

**Interfaces:**
- Consumes: `palettes.<name>` from Task 1 and `ansiSlots` from Task 1b.
- Produces: `themes/<name>/` directories with the anatomy `dot-theme-set` expects, and a `[palette]` section in every `colors.toml`.

**Why `colors.toml` changes shape:** `bin/gen-pi-theme.py:70` reads `toml["catppuccin"]` — a hardcoded section name. A theme called `high-contrast-dark` having a `[catppuccin]` section is nonsense. The section is renamed to `[palette]`, and the reader accepts either so nothing breaks mid-migration.

**The ANSI ordering is not duplicated here.** It comes from `lib/themes.nix`'s `ansiSlots` (Task 1b), passed in as part of the JSON this script reads. Re-declaring the order in Python would be a second source of truth for the same sixteen values — which is the exact defect Task 1b exists to fix.

**btop is deliberately NOT regenerated for the Catppuccin themes.** `themes/catppuccin-latte/btop.theme` uses nine colours that are absent from its palette (`#1a1c28`, `#0d47a1`, `#2d5016`, …) — hand-darkened to read against a light background. Regenerating it from raw palette slots would replace `#0d47a1` with Latte's `blue` (`#1e66f5`, 4.34:1, fails AA), i.e. a contrast regression in a contrast project. The two new palettes need no such tuning: their accents are already ≥7:1 by construction.

- [ ] **Step 1: Create the generator**

Create `bin/gen-theme-dir.py` (mode 755):

```python
#!/usr/bin/env python3
"""Render themes/<name>/ from a palette defined in lib/themes.nix.

lib/themes.nix is the single source of truth for colour. This script projects
one palette into the runtime theme-directory anatomy that bin/dot-theme-set
consumes. Output is committed; this runs at authoring time, not at switch time.

Usage:
  cd ~/dotfiles
  nix eval --json --impure --expr \
    'let t = import ./lib/themes.nix { pkgs = import <nixpkgs> {}; };
     in builtins.mapAttrs (n: p: p // { ansi = t.ansiSlots p; }) t.palettes' \
    | bin/gen-theme-dir.py <theme-name> themes/<theme-name> \
        themes/catppuccin-mocha/btop.theme [--skip-btop]

The ANSI order arrives in the JSON as each palette's `ansi` list, produced by
lib/themes.nix's ansiSlots. It is deliberately NOT redeclared here: two copies
of the same sixteen values is the defect Task 1b fixed.

The btop template's colours are substituted slot-for-slot. Verified to
reproduce the committed catppuccin-mocha btop.theme byte-for-byte.

--skip-btop leaves an existing btop.theme untouched. Used for the catppuccin
themes, whose light-variant btop file is hand-darkened beyond the palette.
"""
import json
import os
import re
import sys

ORDER = ["rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach",
         "yellow", "green", "teal", "sky", "sapphire", "blue", "lavender",
         "text", "subtext1", "subtext0", "overlay2", "overlay1", "overlay0",
         "surface2", "surface1", "surface0", "base", "mantle", "crust"]

UI = [("accent", "blue"), ("foreground", "text"), ("background", "base"),
      ("cursor", "rosewater"), ("selection_foreground", "base"),
      ("selection_background", "rosewater")]


def main():
    palettes = json.load(sys.stdin)
    name, outdir, btop_template = sys.argv[1], sys.argv[2], sys.argv[3]
    skip_btop = "--skip-btop" in sys.argv[4:]
    palette = palettes[name]
    c, variant = palette["colors"], palette["variant"]
    # ANSI order comes from lib/themes.nix via ansiSlots — see the docstring.
    ansi = palette["ansi"]
    os.makedirs(outdir, exist_ok=True)

    def write(filename, text):
        with open(os.path.join(outdir, filename), "w") as fh:
            fh.write(text)

    write("variant", variant + "\n")

    lines = [f"# {name} - single source of truth for all themed apps.",
             "# GENERATED by bin/gen-theme-dir.py from lib/themes.nix.",
             "# Do not hand-edit: change the palette in lib/themes.nix and re-run.",
             "", "[ui]"]
    lines += [f'{key} = "{c[slot]}"' for key, slot in UI]
    lines += ["", "[ansi]"]
    lines += [f'color{i} = "{c[slot]}"' for i, slot in enumerate(ansi)]
    lines += ["", "[palette]"]
    lines += [f'{slot} = "{c[slot]}"' for slot in ORDER]
    write("colors.toml", "\n".join(lines) + "\n")

    sh = [f"# {name} palette - human reference (not consumed by dot-theme-set)",
          "# GENERATED by bin/gen-theme-dir.py from lib/themes.nix."]
    sh += [f'export THEME_{slot.upper()}="{c[slot]}"' for slot in ORDER]
    write("palette.sh", "\n".join(sh) + "\n")

    dark = variant == "dark"
    write("gtk.conf", "\n".join([
        f"# GTK + system color-scheme for {name}",
        "# Consumed by dot-theme-set via `source` - exports key=value vars.",
        "# GENERATED by bin/gen-theme-dir.py from lib/themes.nix.",
        f'GTK_THEME="{"Adwaita-dark" if dark else "Adwaita"}"',
        f'COLOR_SCHEME="{"prefer-dark" if dark else "prefer-light"}"']) + "\n")

    # btop has no generator in lib/themes.nix; its 42 entries draw on 17 palette
    # slots. Reverse-map the template's hexes to slot names, then substitute.
    #
    # Skipped for the catppuccin themes: catppuccin-latte's committed btop.theme
    # uses nine colours absent from its palette, hand-darkened to read on a light
    # background. Regenerating from raw slots would lower its contrast.
    if skip_btop:
        print(f"wrote {outdir} (btop.theme left untouched)")
        return

    reference = palettes["catppuccin-mocha"]["colors"]
    by_hex = {v.lower(): k for k, v in reference.items()}
    with open(btop_template) as fh:
        template = fh.read()
    unknown = {h for h in re.findall(r"#[0-9a-fA-F]{6}", template)
               if h.lower() not in by_hex}
    if unknown:
        sys.exit(f"btop template has colours absent from the reference palette: "
                 f"{sorted(unknown)}")
    write("btop.theme", re.sub(r"#[0-9a-fA-F]{6}",
                               lambda m: c[by_hex[m.group(0).lower()]], template))

    print(f"wrote {outdir}")


main()
```

- [ ] **Step 2: Prove the generator is correct by reproducing a committed theme**

This is the test. If the generator reproduces the hand-written Catppuccin files, its slot mapping is right.

```bash
cd ~/dotfiles
chmod 755 bin/gen-theme-dir.py
PAL=$(mktemp)
nix eval --json --impure --expr 'let t = import ./lib/themes.nix { pkgs = import <nixpkgs> {}; };
  in builtins.mapAttrs (n: p: p // { ansi = t.ansiSlots p; }) t.palettes' > "$PAL"
OUT=$(mktemp -d)
bin/gen-theme-dir.py catppuccin-mocha "$OUT" themes/catppuccin-mocha/btop.theme < "$PAL"
diff "$OUT/btop.theme" themes/catppuccin-mocha/btop.theme && echo "btop.theme IDENTICAL"
diff "$OUT/variant"   themes/catppuccin-mocha/variant   && echo "variant IDENTICAL"
diff <(grep -E '^(GTK_THEME|COLOR_SCHEME)=' "$OUT/gtk.conf") \
     <(grep -E '^(GTK_THEME|COLOR_SCHEME)=' themes/catppuccin-mocha/gtk.conf) \
  && echo "gtk values IDENTICAL"
diff <(sed -n '/^\[ansi\]/,/^$/p' "$OUT/colors.toml") \
     <(sed -n '/^\[ansi\]/,/^$/p' themes/catppuccin-mocha/colors.toml) \
  && echo "ansi section IDENTICAL"
```

Expected: all four "IDENTICAL" lines, no diff output. **If `btop.theme` differs, stop** — the slot mapping is wrong and every generated theme will be wrong.

Then the same check for the light variant, which is what Task 1b fixed. Its `[ansi]` must reproduce too:

```bash
OUTL=$(mktemp -d)
bin/gen-theme-dir.py catppuccin-latte "$OUTL" themes/catppuccin-mocha/btop.theme --skip-btop < "$PAL"
diff <(sed -n '/^\[ansi\]/,/^$/p' "$OUTL/colors.toml") \
     <(git show HEAD:themes/catppuccin-latte/colors.toml | sed -n '/^\[ansi\]/,/^$/p') \
  && echo "latte ansi IDENTICAL — variant-aware ordering confirmed"
```

Expected: `latte ansi IDENTICAL`. If it differs, Task 1b's `ansiSlots` is wrong — stop and report, do not edit the committed file.

- [ ] **Step 3: Generate the four theme directories**

```bash
cd ~/dotfiles
# --skip-btop for the catppuccin themes: latte's committed btop.theme is
# hand-darkened beyond its palette and regenerating it would LOWER contrast.
for t in catppuccin-mocha catppuccin-latte; do
  bin/gen-theme-dir.py "$t" "themes/$t" themes/catppuccin-mocha/btop.theme --skip-btop < "$PAL"
done
for t in high-contrast-dark high-contrast-light; do
  bin/gen-theme-dir.py "$t" "themes/$t" themes/catppuccin-mocha/btop.theme < "$PAL"
done
git diff --stat themes/
```

Expected: the two catppuccin `colors.toml`, `palette.sh` and `gtk.conf` files change (regenerated headers, `[catppuccin]` → `[palette]`); their **`btop.theme` does NOT appear in the diff at all**; two new directories appear.

`themes/catppuccin-latte/variant` **will** show a one-line change: the committed file has no trailing newline (mocha's does) and the generator adds one. That is a harmless pre-existing inconsistency being normalised — `dot-theme-set` reads it as `tr -d '[:space:]' < "$VARIANT_FILE"`, so both forms parse identically. Confirm the content is still the single word `light`, and commit it.

If `themes/catppuccin-latte/btop.theme` shows up in `git diff --stat`, `--skip-btop` did not take — stop and report rather than committing a contrast regression.

- [ ] **Step 4: Write the two READMEs**

`themes/high-contrast-dark/README.md`:

```markdown
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
```

`themes/high-contrast-light/README.md`:

```markdown
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
```

- [ ] **Step 5: Teach `gen-pi-theme.py` the new section name**

In `bin/gen-pi-theme.py`, replace line 70's `c = toml["catppuccin"]` with:

```python
    # Section renamed [catppuccin] -> [palette] on 2026-08-09: the theme set is
    # no longer catppuccin-only. Both are accepted so a stale theme directory
    # keeps working.
    c = toml.get("palette") or toml["catppuccin"]
```

- [ ] **Step 6: Verify pi theme generation still works for every theme**

```bash
cd ~/dotfiles
for t in catppuccin-mocha catppuccin-latte high-contrast-dark high-contrast-light; do
  printf "%-22s " "$t"
  bin/gen-pi-theme.py "themes/$t" > /dev/null && \
    python3 -c "import json;d=json.load(open('themes/$t/pi-agent-theme.json'));print('ok,',len(d),'top-level keys')"
done
```

Expected: four `ok, N top-level keys` lines, no traceback.

- [ ] **Step 7: Delete the superseded ghostty files**

Task 3 makes Nix the source of ghostty theme config, so these become duplicated state:

```bash
cd ~/dotfiles
git rm -q themes/*/ghostty.conf
ls themes/catppuccin-mocha/
```

Expected listing: `README.md btop.theme colors.toml gtk.conf palette.sh pi-agent-theme.json variant` — no `ghostty.conf`.

- [ ] **Step 8: Commit**

```bash
cd ~/dotfiles
git add -A themes bin/gen-theme-dir.py bin/gen-pi-theme.py
git commit -m "feat(theme): generate theme directories from lib/themes.nix

Adds bin/gen-theme-dir.py, which projects a palette into the runtime
theme-directory anatomy, and uses it to create the two high-contrast themes
and regenerate the two catppuccin ones.

The generator is verified by reproduction: run against catppuccin-mocha it
emits a btop.theme byte-identical to the committed hand-written file, with
variant and the [ansi] section likewise identical. That is what establishes
the slot mapping is right, rather than inspection.

colors.toml's [catppuccin] section becomes [palette] — a theme named
high-contrast-dark having a [catppuccin] section is nonsense. gen-pi-theme.py
accepts either, so no theme directory breaks mid-migration.

themes/*/ghostty.conf is deleted: Task 3 makes Nix pre-render those, and
keeping both would be two sources of truth for the same file."
```

---

## Task 3: Fix ghostty's dual ownership

**Agent-executable.**

**Files:**
- Modify: `ioshi/i-intelligence/ghostty.nix`
- Modify: `bin/dot-theme-set`

**Interfaces:**
- Consumes: `palettes` from Task 1.
- Produces: `~/.config/ghostty/themes/<name>.conf` for all four themes, and an unmanaged `~/.config/ghostty/theme.conf` symlink that `dot-theme-set` owns.

**The bug being fixed:** `ghostty.nix` declares `home.file.".config/ghostty/theme.conf"` while `dot-theme-set` does `ln -sfn` over the same path. Home Manager wins at every activation, renaming the runtime symlink to `theme.conf.hm-bak`. So the first theme switch is reverted by the next `nixos-rebuild switch`. `ghostty.nix` already says *"Pre-generate all theme variants so the runtime switcher can flip symlinks"* — the `theme.conf` declaration contradicts that.

- [ ] **Step 1: Replace the theme-file block in `ghostty.nix`**

Delete this block entirely:

```nix
    home.file.".config/ghostty/theme.conf" = {
      text = ghostty activePalette;
    };

    # Pre-generate all theme variants so the runtime switcher can flip symlinks.
    home.file.".config/ghostty/themes/catppuccin-mocha.conf" = {
      text = ghostty palettes.catppuccin-mocha;
    };

    home.file.".config/ghostty/themes/catppuccin-latte.conf" = {
      text = ghostty palettes.catppuccin-latte;
    };
```

Replace it with:

**The module already has a `home.file.".config/ghostty/config"` assignment.** You cannot add a second `home.file = ...` beside it — Nix rejects two assignments to the same attribute path in one attrset literal ("attribute already defined"). Merge them into a single `home.file` expression with `//`, keeping the existing `config` entry's text exactly as it is:

```nix
    # Every palette is pre-rendered here; the runtime switcher picks one.
    # theme.conf is deliberately NOT declared as home.file: bin/dot-theme-set
    # owns that path, and two owners means Home Manager renames the runtime
    # symlink to theme.conf.hm-bak at every activation — silently reverting
    # the active theme on the next rebuild.
    home.file = lib.mapAttrs'
      (name: palette: lib.nameValuePair
        ".config/ghostty/themes/${name}.conf"
        { text = ghostty palette; })
      palettes
    // {
      ".config/ghostty/config" = { text = ''<the existing config text, unchanged>''; };
    };

    # Seed theme.conf only when absent, so a fresh machine has a theme before
    # the first dot-theme-set run. `-e` is false for a dangling symlink, which
    # is the case worth re-seeding, so this is the right test.
    home.activation.seedGhosttyTheme =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        target="$HOME/.config/ghostty/theme.conf"
        if [ ! -e "$target" ]; then
          run ln -sfn "$HOME/.config/ghostty/themes/${config.scott.theme}.conf" "$target"
        fi
      '';
```

- [ ] **Step 2: Point `dot-theme-set` at the Nix-rendered variants**

In `bin/dot-theme-set`, replace this line:

```bash
link_if_present "$THEME_DIR/ghostty.conf"   "$HOME/.config/ghostty/theme.conf"
```

with:

```bash
# ghostty configs are rendered by Nix into ~/.config/ghostty/themes/, not
# carried in themes/<name>/ — lib/themes.nix is the single source of colour.
link_if_present "$HOME/.config/ghostty/themes/$THEME_NAME.conf" \
                "$HOME/.config/ghostty/theme.conf"
```

- [ ] **Step 3: Verify all four variants are rendered, and `theme.conf` is not**

```bash
cd ~/dotfiles
nixpkgs-fmt --check ioshi/i-intelligence/ghostty.nix
nix eval --json .#nixosConfigurations.rafik.config.home-manager.users.scott.home.file \
  --apply 'f: builtins.filter (n: builtins.match ".*ghostty.*" n != null) (builtins.attrNames f)'
```

Expected: the four `.config/ghostty/themes/<name>.conf` entries plus `.config/ghostty/config`, and **no** `.config/ghostty/theme.conf`.

- [ ] **Step 4: Build all three hosts**

```bash
cd ~/dotfiles
for h in rafik whistle datacore; do
  printf "%-9s " $h
  nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel
done
```

Expected: all three succeed. rafik and whistle change (ghostty is enabled on both); datacore should be unchanged — record its path and compare.

- [ ] **Step 5: Commit**

```bash
git add ioshi/i-intelligence/ghostty.nix bin/dot-theme-set
git commit -m "fix(ghostty): one owner for theme.conf

home.file declared .config/ghostty/theme.conf while dot-theme-set symlinked
over the same path. Home Manager wins at every activation, renaming the
runtime symlink to theme.conf.hm-bak — so the first theme switch would be
silently reverted by the next nixos-rebuild switch. The module's own comment
already described the intended split; the declaration contradicted it.

Nix now renders every palette into ~/.config/ghostty/themes/ via mapAttrs',
so adding a palette adds its ghostty config with no further edit, and
dot-theme-set owns theme.conf alone. An activation hook seeds that symlink
only when absent, so a fresh machine still has a theme before the first
switch. The absent-test uses -e, which is false for a dangling symlink —
exactly the case that should be re-seeded."
```

---

## Task 4: Make the Emacs layer theme-agnostic

**Agent-executable.**

**Files:**
- Rewrite: `ioshi/i-intelligence/emacs/lisp/scott-theme.el`
- Create: `themes/catppuccin-mocha/emacs-theme`, `themes/catppuccin-latte/emacs-theme`, `themes/high-contrast-dark/emacs-theme`, `themes/high-contrast-light/emacs-theme`
- Modify: `bin/dot-theme-set`

**Interfaces:**
- Consumes: `themes/<name>/emacs-theme` and `themes/<name>/variant`.
- Produces: `(scott/theme-set "<theme-name>")` — takes a **dotfiles theme name**, not a Catppuccin flavor. `scott/theme-init` takes no argument.

**Two bugs being fixed:**
1. `scott-theme.el` is hard-wired to Catppuccin: `(if (string-match-p "latte" name) 'latte 'mocha)` turns any non-latte name into Mocha, so `high-contrast-dark` is inexpressible.
2. `dot-theme-set` calls `$HOME/.nix-profile/bin/emacsclient`, which **does not exist on rafik** — the EWM build's client is `/run/current-system/sw/bin/emacsclient`. The call is wrapped in `|| true`, so this has been failing silently on the only EWM host.

**Verified Modus facts** (Emacs 30.2, checked 2026-08-09) — get these wrong and the theme silently renders at 21:1 instead of the intended 16:1:
- Modus ships in `<emacs>/share/emacs/30.2/etc/themes/`, so no package is needed.
- That directory is on `custom-theme-load-path` but **not** on `load-path`, so `(require 'modus-themes)` fails until `load-path` is extended.
- `modus-themes-common-palette-overrides` must be set **before** `load-theme`.
- Verification uses `(modus-themes-with-colors (list bg-main fg-main))`. Note `modus-themes-get-color-value` returns the *un*-overridden value unless its second argument is non-nil.

- [ ] **Step 1: Write the four `emacs-theme` files**

```bash
cd ~/dotfiles
echo catppuccin    > themes/catppuccin-mocha/emacs-theme
echo catppuccin    > themes/catppuccin-latte/emacs-theme
echo modus-vivendi > themes/high-contrast-dark/emacs-theme
echo modus-operandi > themes/high-contrast-light/emacs-theme
for t in themes/*/emacs-theme; do printf "%-45s %s\n" "$t" "$(cat $t)"; done
```

- [ ] **Step 2: Rewrite `scott-theme.el`**

Replace the entire file with:

```elisp
;;; scott-theme.el --- dotfiles theme control -*- lexical-binding: t; -*-

;; The active theme is named in ~/.config/dotfiles/active-theme, and each
;; themes/<name>/ directory carries an `emacs-theme' file naming the Emacs
;; theme to load. bin/dot-theme-set calls (scott/theme-set "<name>") on switch.
;;
;; This used to take a catppuccin flavor ("mocha"/"latte") and derive it with
;; (string-match-p "latte" name), which silently mapped every other theme name
;; to mocha — so a non-catppuccin theme could not be expressed at all.

(require 'catppuccin-theme nil :no-error)

;; Modus ships inside Emacs at <emacs>/share/emacs/<ver>/etc/themes, which is on
;; custom-theme-load-path but NOT on load-path — so `load-theme' finds the
;; themes while `require' cannot find modus-themes.el, where the palette-override
;; variable is defined. Extend load-path so the overrides below actually apply.
(add-to-list 'load-path (expand-file-name "themes/" data-directory))

(defconst scott-theme--state-file "~/.config/dotfiles/active-theme")
(defconst scott-theme--themes-dir "~/dotfiles/themes")
(defconst scott-theme--default "catppuccin-mocha")

;; bg-main/fg-main per theme. These MUST match lib/themes.nix's base/text for
;; the same theme: Modus defaults to 19-21:1 (modus-vivendi is #000/#fff), and
;; the spec deliberately targets ~16:1 to avoid halation.
(defconst scott-theme--modus-overrides
  '(("high-contrast-dark"  . ((bg-main "#0a0a0a") (fg-main "#e8e8e8")))
    ("high-contrast-light" . ((bg-main "#f2f2f2") (fg-main "#111111")))))

(defun scott-theme--read (path)
  "Return the trimmed contents of PATH, or nil if unreadable."
  (when (file-readable-p path)
    (string-trim (with-temp-buffer (insert-file-contents path) (buffer-string)))))

(defun scott-theme--active-name ()
  "Name of the active dotfiles theme."
  (or (scott-theme--read scott-theme--state-file) scott-theme--default))

(defun scott-theme--emacs-theme (name)
  "Emacs theme symbol for dotfiles theme NAME."
  (intern (or (scott-theme--read
               (expand-file-name (format "%s/emacs-theme" name)
                                 scott-theme--themes-dir))
              "catppuccin")))

(defun scott/theme-set (name)
  "Switch the running session to dotfiles theme NAME."
  (interactive "sTheme name: ")
  (let ((theme (scott-theme--emacs-theme name)))
    (setq modus-themes-common-palette-overrides
          (cdr (assoc name scott-theme--modus-overrides)))
    (when (eq theme 'catppuccin)
      (setq catppuccin-flavor (if (string-match-p "latte" name) 'latte 'mocha)))
    (mapc #'disable-theme custom-enabled-themes)
    (load-theme theme :no-confirm)
    (when (eq theme 'catppuccin) (catppuccin-reload))
    theme))

(defun scott/theme-init ()
  "Load the theme matching the active dotfiles theme."
  (scott/theme-set (scott-theme--active-name)))

(provide 'scott-theme)
;;; scott-theme.el ends here
```

- [ ] **Step 3: Test every theme loads and resolves to the right colours**

```bash
cd ~/dotfiles
timeout 120 emacs --batch \
  -L ioshi/i-intelligence/emacs/lisp \
  --eval '(progn
    (require (quote scott-theme))
    (dolist (n (list "catppuccin-mocha" "catppuccin-latte"
                     "high-contrast-dark" "high-contrast-light"))
      (let ((th (scott/theme-set n)))
        (message "%-22s -> %-16s enabled=%S" n th custom-enabled-themes)))
    (scott/theme-set "high-contrast-dark")
    (message "HC-dark  bg/fg: %S" (modus-themes-with-colors (list bg-main fg-main)))
    (scott/theme-set "high-contrast-light")
    (message "HC-light bg/fg: %S" (modus-themes-with-colors (list bg-main fg-main))))' \
  2>&1 | grep -vE "^Loading"
```

Expected:

```
catppuccin-mocha       -> catppuccin       enabled=(catppuccin)
catppuccin-latte       -> catppuccin       enabled=(catppuccin)
high-contrast-dark     -> modus-vivendi    enabled=(modus-vivendi)
high-contrast-light    -> modus-operandi   enabled=(modus-operandi)
HC-dark  bg/fg: ("#0a0a0a" "#e8e8e8")
HC-light bg/fg: ("#f2f2f2" "#111111")
```

If the bg/fg lines read `("#000000" "#ffffff")` or `("#ffffff" "#000000")`, the overrides are not applying — check that the `load-path` line is present and runs before `require`.

- [ ] **Step 4: Fix the emacsclient handoff in `dot-theme-set`**

Replace the whole Emacs block (the one starting `# --- Emacs: switch catppuccin flavor`) with:

```bash
# --- Emacs: switch theme in the running daemon (best-effort) ---
# Resolve emacsclient rather than hardcoding a path. rafik runs the
# system-owned EWM build, whose client is /run/current-system/sw/bin/
# emacsclient; ~/.nix-profile/bin/emacsclient does not exist there at all.
# The old hardcoded path meant this handoff silently no-op'd on the one host
# where Emacs IS the desktop.
EMACSCLIENT="$(command -v emacsclient || true)"
if [[ -n "$EMACSCLIENT" ]]; then
    # Pass the theme NAME. Emacs maps it via themes/<name>/emacs-theme, so a
    # new theme needs no change here.
    "$EMACSCLIENT" -e "(scott/theme-set \"$THEME_NAME\")" &>/dev/null || true
fi
```

- [ ] **Step 5: Confirm the old hardcoded path is gone**

```bash
cd ~/dotfiles
grep -n "nix-profile/bin/emacsclient" bin/dot-theme-set || echo "hardcoded path gone"
grep -n "emacs_flavor" bin/dot-theme-set || echo "flavor derivation gone"
bash -n bin/dot-theme-set && echo "dot-theme-set parses"
```

Expected: both "gone" lines, plus "dot-theme-set parses".

- [ ] **Step 6: Commit**

```bash
git add ioshi/i-intelligence/emacs/lisp/scott-theme.el themes/*/emacs-theme bin/dot-theme-set
git commit -m "feat(emacs): theme by name, not by catppuccin flavor

scott/theme-set took a catppuccin flavor and derived it with
(string-match-p \"latte\" name), mapping every other theme name to mocha. A
high-contrast theme could not be expressed. It now takes a dotfiles theme
name and reads themes/<name>/emacs-theme, so adding a theme is a directory
copy with no elisp change — matching how the rest of the theme system works.

High-contrast themes use Modus, which ships with Emacs 30.2. Two details
that are easy to get silently wrong, both verified:

- etc/themes is on custom-theme-load-path but NOT load-path, so
  (require 'modus-themes) fails and the palette-override variable is never
  defined. load-path is extended explicitly.
- Modus defaults to 19-21:1 (modus-vivendi is #000/#fff), which is the
  halation case the spec rejects. bg-main/fg-main are overridden to the
  palette's base/text so Emacs matches the ~16:1 target.

Also fixes dot-theme-set's hardcoded ~/.nix-profile/bin/emacsclient. That
path does not exist on rafik, whose EWM client is in /run/current-system;
wrapped in || true, the handoff had been failing silently on the only host
where Emacs is the desktop."
```

---

## Task 5: Firefox chrome theming

**Agent-executable.**

**Files:**
- Modify: `lib/themes.nix`
- Modify: `ioshi/i-intelligence/firefox.nix`

**Interfaces:**
- Consumes: `palettes` from Task 1.
- Produces: `firefoxChrome` generator; per-theme `userChrome.css` in the Firefox profile.

**Scope reminder:** chrome only. Page content is untouched — see spec decision 3. Do **not** add `browser.display.document_color_use`.

- [ ] **Step 1: Add the generator to `lib/themes.nix`**

After the `ghostty` generator, add:

```nix
  # Firefox browser chrome (toolbar/tabs/urlbar). Chrome only — page content is
  # deliberately untouched (spec decision 3). Requires
  # toolkit.legacyUserProfileCustomizations.stylesheets = true, set in
  # firefox.nix; without it Firefox ignores userChrome.css entirely.
  firefoxChrome = palette: ''
    /* Generated by dotfiles/lib/themes.nix — ${palette.variant} variant */
    :root {
      --ctp-base: ${palette.colors.base};
      --ctp-mantle: ${palette.colors.mantle};
      --ctp-crust: ${palette.colors.crust};
      --ctp-text: ${palette.colors.text};
      --ctp-subtext0: ${palette.colors.subtext0};
      --ctp-surface0: ${palette.colors.surface0};
      --ctp-surface1: ${palette.colors.surface1};
      --ctp-accent: ${palette.colors.blue};
    }

    #navigator-toolbox {
      background-color: var(--ctp-mantle) !important;
      border-bottom: 1px solid var(--ctp-surface0) !important;
    }

    #TabsToolbar, #nav-bar, #PersonalToolbar {
      background-color: var(--ctp-mantle) !important;
      color: var(--ctp-text) !important;
    }

    .tabbrowser-tab .tab-content {
      color: var(--ctp-subtext0) !important;
    }

    .tabbrowser-tab[selected] .tab-content {
      color: var(--ctp-text) !important;
    }

    .tabbrowser-tab[selected] .tab-background {
      background-color: var(--ctp-base) !important;
      border-top: 2px solid var(--ctp-accent) !important;
    }

    #urlbar, #searchbar {
      background-color: var(--ctp-surface0) !important;
      color: var(--ctp-text) !important;
      border: 1px solid var(--ctp-surface1) !important;
    }

    #urlbar[focused="true"] {
      border-color: var(--ctp-accent) !important;
    }

    #sidebar-box, #sidebar-header {
      background-color: var(--ctp-mantle) !important;
      color: var(--ctp-text) !important;
    }
  '';
```

Add it to `mkTheme`:

```nix
  mkTheme = palette: {
    ghostty = ghostty palette;
    swaylock = swaylock palette;
    firefoxChrome = firefoxChrome palette;
    variant = palette.variant;
    colors = palette.colors;
  };
```

- [ ] **Step 2: Wire it into `firefox.nix`**

In `ioshi/i-intelligence/firefox.nix`, add to the `let` block at the top:

```nix
  themeLib = import ../../lib/themes.nix { inherit pkgs; };
  palettes = themeLib.palettes;
  activePalette = palettes.${config.scott.theme} or palettes.catppuccin-mocha;
```

Note this file's argument list currently omits `pkgs` (it was removed when the
Catppuccin block went). Restore it: `{ config, lib, pkgs, ... }:`.

Inside `profiles.default`, add:

```nix
        # Chrome only, by design: catppuccin's firefox port themed the browser
        # UI by installing the FirefoxColor extension, and page content is
        # left exactly as authored. To force the palette onto page content
        # too, set browser.display.document_color_use = 2 here — see spec
        # decision 3 for why that is not the default.
        userChrome = themeLib.firefoxChrome activePalette;
```

And in the profile's `settings`, add:

```nix
          # Without this Firefox ignores userChrome.css entirely.
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
```

- [ ] **Step 3: Verify the CSS is generated and reaches the profile**

```bash
cd ~/dotfiles
nixpkgs-fmt --check lib/themes.nix ioshi/i-intelligence/firefox.nix
nix eval --raw .#nixosConfigurations.rafik.config.home-manager.users.scott.programs.firefox.profiles.default.userChrome \
  | head -12
```

Expected: the generated CSS beginning `/* Generated by dotfiles/lib/themes.nix — dark variant */` with `--ctp-base: #1e1e2e;` (rafik's `scott.theme` is `catppuccin-mocha`).

- [ ] **Step 4: Confirm no content override slipped in**

```bash
cd ~/dotfiles
grep -rn "document_color_use" . --include='*.nix' && echo "UNEXPECTED — spec decision 3 says chrome only" || echo "no content override, correct"
```

- [ ] **Step 5: Build; whistle and datacore must be unchanged**

```bash
cd ~/dotfiles
for h in rafik whistle datacore; do
  printf "%-9s " $h
  nix build --no-link --print-out-paths .#nixosConfigurations.$h.config.system.build.toplevel
done
```

Expected: rafik changes (`scott.gui = true`). whistle and datacore must be **unchanged** — `firefox.nix` is gated on `scott.gui`, which is false on both. If either moves, the gating broke.

- [ ] **Step 6: Commit**

```bash
git add lib/themes.nix ioshi/i-intelligence/firefox.nix
git commit -m "feat(firefox): theme the browser chrome from the active palette

Adds a firefoxChrome generator and wires it to programs.firefox's userChrome,
plus the legacyUserProfileCustomizations pref without which Firefox ignores
the stylesheet entirely.

Chrome only, deliberately. Forcing the palette onto page content is one pref
(browser.display.document_color_use = 2) and is the larger accessibility
lever, since content is the overwhelming majority of the window — but it
breaks sites that hardcode colours without honouring forced-colors. Recorded
as an extension point in the spec and in the module, not shipped.

Restores pkgs to the module's argument list; it was dropped when the dead
catppuccin block was removed and is needed to import lib/themes.nix."
```

---

## Task 6: zellij follows the terminal

**Agent-executable.**

**Files:**
- Modify: `ioshi/i-intelligence/zellij/config.kdl`
- Modify: `ioshi/i-intelligence/zellij.nix`
- Modify: `bin/dot-theme-set`

**Interfaces:**
- Produces: `~/.local/share/dotfiles/zellij-themes/active/theme.kdl` — a symlink to one of `available/eminix-{dark,light}.kdl`, flipped by `dot-theme-set`. Both files define a theme named `eminix`.

**Why indices, not hex:** Scott runs Claude Code on whistle either locally or ssh'd from rafik. Under ssh the *rendering* terminal is rafik's ghostty, so hardcoded per-host colours would clash. Zellij colour indices 0–15 resolve against whatever terminal renders them. **Verified:** zellij 0.44.3 accepts bare indices — a theme written `fg 15` / `bg 0` passes `zellij setup --check` with `[CONFIG FILE]: Well defined.`

**Why the theme file lives outside the repo:** `~/.config/zellij` is an out-of-store symlink into the checkout (`zellij.nix`), so writing a theme there at switch time would dirty the working tree — the Helix drift caveat.

**Three zellij behaviours verified 2026-08-09 that dictate the shape below.** Get any of them wrong and the switcher silently does nothing:

- **zellij selects a theme by NAME, not by file.** So the two theme files must both define a theme with the *same* name (`eminix`), and `theme_dir` must contain only the active one. Putting both files in `theme_dir` and changing the `theme` line would require editing `config.kdl` — which is in the checkout, and would dirty the tree on every switch.
- **`theme_dir` pointing at a missing directory is a hard `IoError`** and zellij refuses to start. The directory and its symlink must exist before zellij ever runs, so Home Manager seeds them.
- **`zellij setup --check` does NOT validate theme names.** A config naming a nonexistent theme still reports `[CONFIG FILE]: Well defined.` The check confirms KDL syntax and colour-value parsing only. Real theme resolution is verified on the machine in Task 9 — do not treat a passing `--check` as proof the theme applies.

- [ ] **Step 1: Create the two theme files under Home Manager**

In `ioshi/i-intelligence/zellij.nix`, inside `config = lib.mkIf ...`, add:

```nix
    # Themes live OUTSIDE the checkout. ~/.config/zellij is an out-of-store
    # symlink into the repo, so a theme file written there at switch time would
    # dirty the working tree — the Helix drift caveat in docs/manual/02-theming.md.
    #
    # Colours are ANSI indices 0-15, not hex, on purpose: they resolve against
    # whatever terminal renders the session. Under ssh from rafik into whistle
    # the rendering terminal is rafik's ghostty, so hardcoded per-host colours
    # would clash. This also means a palette switch needs no zellij change at
    # all — only the dark/light role assignment differs below.
    #
    # BOTH themes are named `eminix`, deliberately. zellij selects a theme by
    # name, so switching is done by changing WHICH FILE is visible in theme_dir,
    # not by editing the `theme` line in config.kdl (which lives in the repo and
    # must stay clean). available/ is not theme_dir; active/ is.
    home.file.".local/share/dotfiles/zellij-themes/available/eminix-dark.kdl".text = ''
      themes {
          eminix {
              fg 7
              bg 0
              black 0
              red 1
              green 2
              yellow 3
              blue 4
              magenta 5
              cyan 6
              white 15
              orange 3
          }
      }
    '';

    home.file.".local/share/dotfiles/zellij-themes/available/eminix-light.kdl".text = ''
      themes {
          eminix {
              fg 0
              bg 15
              black 0
              red 1
              green 2
              yellow 3
              blue 4
              magenta 5
              cyan 6
              white 7
              orange 3
          }
      }
    '';

    # theme_dir must EXIST before zellij starts: pointing it at a missing
    # directory is a hard IoError, not a warning, and zellij refuses to run.
    # Seed the active symlink if absent, same pattern as ghostty's theme.conf.
    home.activation.seedZellijTheme =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        active="$HOME/.local/share/dotfiles/zellij-themes/active"
        run mkdir -p "$active"
        if [ ! -e "$active/theme.kdl" ]; then
          run ln -sfn \
            "$HOME/.local/share/dotfiles/zellij-themes/available/eminix-dark.kdl" \
            "$active/theme.kdl"
        fi
      '';
```

- [ ] **Step 2: Point `config.kdl` at the active directory**

In `ioshi/i-intelligence/zellij/config.kdl`, add near the top (uncommented, unlike the surrounding documentation block):

```kdl
// Theme comes from ~/.local/share/dotfiles/zellij-themes/active/, which holds
// exactly one file: a symlink flipped by bin/dot-theme-set. Both candidate
// themes are named `eminix`, so this line never changes — zellij selects by
// theme NAME, and switching swaps which definition is visible.
//
// Kept outside the repo because ~/.config/zellij is a live symlink into the
// checkout and must stay clean. This directory must exist or zellij fails to
// start with an IoError; Home Manager creates and seeds it.
theme_dir "/home/scott/.local/share/dotfiles/zellij-themes/active"
theme "eminix"
```

- [ ] **Step 3: Add the zellij flip to `dot-theme-set`**

After the btop `link_if_present` line, add:

```bash
# --- zellij: flip which ANSI-index theme is active ---
# Colours come from the terminal, so only the dark/light role assignment
# changes here. Both candidate themes are named `eminix`; zellij selects by
# name, so the switch swaps which definition is visible in theme_dir rather
# than editing config.kdl (which lives in the checkout and must stay clean).
zellij_root="$HOME/.local/share/dotfiles/zellij-themes"
if [[ -d "$zellij_root/available" ]]; then
    mkdir -p "$zellij_root/active"
    ln -sfn "$zellij_root/available/eminix-$VARIANT.kdl" \
            "$zellij_root/active/theme.kdl"
fi
```

- [ ] **Step 4: Verify both themes parse, and that the switch is observable**

```bash
cd ~/dotfiles
root=$(mktemp -d); mkdir -p "$root/available" "$root/active"
for v in dark light; do
  nix eval --raw ".#nixosConfigurations.rafik.config.home-manager.users.scott.home.file.\".local/share/dotfiles/zellij-themes/available/eminix-$v.kdl\".text" \
    > "$root/available/eminix-$v.kdl"
done
printf 'theme_dir "%s/active"\ntheme "eminix"\n' "$root" > "$root/config.kdl"
for v in dark light; do
  ln -sfn "$root/available/eminix-$v.kdl" "$root/active/theme.kdl"
  printf "eminix-%-6s " "$v"
  zellij --config "$root/config.kdl" setup --check 2>&1 | grep -E "CONFIG FILE" || echo "CHECK FAILED"
done
echo "--- both files define a theme named 'eminix'? ---"
grep -h -A1 "^themes" "$root"/available/*.kdl | grep -c "eminix {"
echo "--- and they actually differ? ---"
diff -q "$root/available/eminix-dark.kdl" "$root/available/eminix-light.kdl" \
  && echo "IDENTICAL — wrong, dark and light must differ" || echo "differ, correct"
```

Expected: `[CONFIG FILE]: Well defined.` twice, a count of `2`, and `differ, correct`.

**This proves syntax and structure only.** `setup --check` accepts a nonexistent theme name without complaint, so it cannot prove the theme resolves — Task 9 does that on the machine.

- [ ] **Step 5: Confirm nothing writes into the checkout**

```bash
cd ~/dotfiles
grep -n "DOTFILES.*zellij\|ioshi/i-intelligence/zellij" bin/dot-theme-set \
  && echo "UNEXPECTED — would dirty the repo" || echo "zellij writes stay outside the checkout"
bash -n bin/dot-theme-set && echo "dot-theme-set parses"
```

- [ ] **Step 6: Commit**

```bash
git add ioshi/i-intelligence/zellij.nix ioshi/i-intelligence/zellij/config.kdl bin/dot-theme-set
git commit -m "feat(zellij): theme from the terminal's ANSI palette

zellij themes are written in colour indices 0-15 rather than hex, so they
resolve against whatever terminal renders the session. That is the correct
behaviour for the ssh case: running zellij on whistle from rafik means the
rendering terminal is rafik's ghostty, and hardcoded per-host colours would
clash with it. It also means switching palette needs no zellij change at
all — only dark/light does.

Verified zellij 0.44.3 accepts bare indices: a theme written fg 15 / bg 0
passes zellij setup --check with '[CONFIG FILE]: Well defined.'

Theme files live in ~/.local/share/dotfiles/zellij-themes rather than the
config dir, because ~/.config/zellij is an out-of-store symlink into the
checkout and writing there at switch time would dirty the working tree."
```

---

## Task 7: Claude Code follows the terminal

**Agent-executable.**

**Files:**
- Modify: `ioshi/i-intelligence/claude/settings.json`
- Modify: `bin/dot-theme-set`

**Interfaces:**
- Produces: a `theme` key of `dark-ansi` or `light-ansi` in `~/.claude/settings.json`.

**Why the `-ansi` variants:** they take colours from the terminal palette rather than Claude's built-ins, so Claude Code inherits high contrast automatically — over ssh, with no per-host state. Only the dark/light axis ever changes; a palette switch needs no Claude change.

**Accepted cost:** `~/.claude/settings.json` is an out-of-store symlink into the checkout, and `claude.nix` already documents runtime writes dirtying the tree as a deliberate trade-off. This key joins that. It is the **only** exception to the no-writes rule.

- [ ] **Step 1: Add the key to the committed settings**

Add `"theme": "dark-ansi"` to `ioshi/i-intelligence/claude/settings.json`, keeping the existing keys (`model`, `hooks`, `enabledPlugins`, `tui`) intact:

```bash
cd ~/dotfiles
python3 - <<'PY'
import json, collections
p = "ioshi/i-intelligence/claude/settings.json"
d = json.load(open(p), object_pairs_hook=collections.OrderedDict)
d["theme"] = "dark-ansi"
json.dump(d, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
python3 -c "import json;print(sorted(json.load(open('ioshi/i-intelligence/claude/settings.json'))))"
```

Expected: `['enabledPlugins', 'hooks', 'model', 'theme', 'tui']`

- [ ] **Step 2: Add the switch to `dot-theme-set`**

Next to the existing pi `settings.json` edit, add:

```bash
# --- Claude Code: follow the terminal palette ---
# The -ansi theme variants take their colours from the terminal rather than
# Claude's built-ins, so Claude inherits whatever palette ghostty is using —
# including over ssh, where the rendering terminal belongs to the client.
# Only the dark/light axis matters here; the palette needs no mention.
#
# This writes inside the checkout (~/.claude/settings.json is an out-of-store
# symlink into it). That is the documented trade-off in claude.nix, and the
# one place the theme system is allowed to dirty the tree.
claude_settings="$HOME/.claude/settings.json"
if [[ -f "$claude_settings" ]] && command -v python3 &>/dev/null; then
    python3 - "$claude_settings" "$VARIANT" <<'PY' || true
import json, sys, collections
path, variant = sys.argv[1], sys.argv[2]
try:
    with open(path) as fh:
        data = json.load(fh, object_pairs_hook=collections.OrderedDict)
except Exception:
    sys.exit(0)
data["theme"] = "light-ansi" if variant == "light" else "dark-ansi"
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
fi
```

- [ ] **Step 3: Test the edit logic without touching the live file**

```bash
cd ~/dotfiles
tmp=$(mktemp); cp ioshi/i-intelligence/claude/settings.json "$tmp"
for v in light dark; do
  python3 - "$tmp" "$v" <<'PY'
import json, sys, collections
path, variant = sys.argv[1], sys.argv[2]
with open(path) as fh:
    data = json.load(fh, object_pairs_hook=collections.OrderedDict)
data["theme"] = "light-ansi" if variant == "light" else "dark-ansi"
with open(path, "w") as fh:
    json.dump(data, fh, indent=2); fh.write("\n")
PY
  printf "%-6s -> %s | keys preserved: %s\n" "$v" \
    "$(python3 -c "import json;print(json.load(open('$tmp'))['theme'])")" \
    "$(python3 -c "import json;print(sorted(json.load(open('$tmp'))))")"
done
```

Expected: `light -> light-ansi` and `dark -> dark-ansi`, with all five keys present both times.

- [ ] **Step 4: Commit**

```bash
git add ioshi/i-intelligence/claude/settings.json bin/dot-theme-set
git commit -m "feat(claude): follow the terminal palette via the -ansi themes

Claude Code's dark-ansi/light-ansi themes take their colours from the
terminal rather than Claude's built-ins, so Claude inherits whatever palette
ghostty is running — including high contrast, and including over ssh, where
the rendering terminal belongs to the client rather than the host.

Only the dark/light axis is written; a palette switch needs no change here.

This is the one place the theme system writes inside the checkout, because
~/.claude/settings.json is an out-of-store symlink into it. claude.nix
already documents that trade-off for this file."
```

---

## Task 8: Documentation

**Agent-executable.**

**Files:**
- Modify: `docs/manual/02-theming.md`

- [ ] **Step 1: Update the shipped-themes list**

Replace the "Shipped themes" block with:

```markdown
## Shipped themes

```
themes/
├── catppuccin-mocha/     # dark  — soft, the daily default
├── catppuccin-latte/     # light — soft
├── high-contrast-dark/   # dark  — 16.16:1
└── high-contrast-light/  # light — 16.87:1
```

`dot-theme-toggle` flips dark↔light within the last-used theme of each
variant, so it stays a two-way toggle even with four themes. Choosing high
contrast is an explicit `dot-theme-set`.

The high-contrast pair exists for accessibility (visual snow syndrome), not
aesthetics. Every accent slot clears WCAG AAA (7:1) against its base;
`tests/contrast-check.py` enforces that. Catppuccin is exempt by name — it is
knowingly soft, and Latte fails AA in three of four sampled pairs.
```

- [ ] **Step 2: Update the anatomy block**

Replace the theme-directory anatomy with:

```markdown
```
themes/catppuccin-mocha/
├── variant            # "dark" or "light" — single word
├── colors.toml        # the palette; [ui] [ansi] [palette] sections
├── palette.sh         # colors as shell vars (reference only; not consumed)
├── emacs-theme        # Emacs theme to load, e.g. "catppuccin", "modus-vivendi"
├── btop.theme         # btop theme → ~/.config/btop/themes/active.theme
├── gtk.conf           # GTK_THEME + COLOR_SCHEME (sourced by dot-theme-set)
├── pi-agent-theme.json # generated from colors.toml by bin/gen-pi-theme.py
├── README.md          # theme origin, contrast figures
└── post-set.sh        # optional hook run at the end of dot-theme-set
```

**These files are generated, not hand-written.** `bin/gen-theme-dir.py`
renders them from the palette in `lib/themes.nix`, which is the single source
of truth for colour. To change a colour, edit the palette and re-run the
generator — do not edit these files directly.

`ghostty.conf` is **not** here: ghostty configs are rendered by Nix into
`~/.config/ghostty/themes/<name>.conf`, and `dot-theme-set` symlinks one of
those to `~/.config/ghostty/theme.conf`. Home Manager deliberately does not
declare `theme.conf` — two owners for that path meant every rebuild silently
reverted the active theme.
```

- [ ] **Step 3: Rewrite the `dot-theme-set` steps**

Replace the numbered "How `dot-theme-set <name>` works" list with:

```markdown
1. Validates `themes/<name>/` exists; refuses unknown names.
2. Reads `variant` (must be `dark` or `light`).
3. Writes `~/.config/dotfiles/active-theme` = `<name>` and `last-<variant>` = `<name>`.
4. Symlinks `~/.config/ghostty/themes/<name>.conf` → `~/.config/ghostty/theme.conf`,
   and `btop.theme` → `~/.config/btop/themes/active.theme`.
5. Symlinks `available/eminix-<variant>.kdl` → `active/theme.kdl` in
   `~/.local/share/dotfiles/zellij-themes/`. Both definitions are named
   `eminix`, so zellij's `theme` line never changes.
6. Writes Claude Code's `theme` key to `dark-ansi`/`light-ansi`.
7. Regenerates `pi-agent-theme.json` from `colors.toml` and points pi's
   `settings.json` at it.
8. Sources `gtk.conf` and runs `gsettings` for `color-scheme` and `gtk-theme`.
9. Calls `(scott/theme-set "<name>")` in the running Emacs daemon, resolving
   `emacsclient` from `PATH`. Emacs maps the name via `themes/<name>/emacs-theme`.
10. Runs `themes/<name>/post-set.sh` if present and executable.
11. Signals ghostty (`SIGUSR2`) to reload.

zellij and Claude Code are themed by **terminal ANSI colours**, not by hex, so
they follow whichever terminal renders them — including over ssh, where that
terminal belongs to the client. Only the dark/light axis is written for them.
```

- [ ] **Step 4: Correct the omissions list**

Replace the "Not handled by the theme system (yet)" list with:

```markdown
- **Firefox page content.** Chrome is themed; page colours are left as
  authored. Forcing the palette onto content is one pref
  (`browser.display.document_color_use = 2` in `firefox.nix`) and is the
  bigger accessibility lever, but it breaks sites that hardcode colours
  without honouring `forced-colors`. Deliberately not enabled — see
  `docs/superpowers/specs/2026-08-09-theming-high-contrast-design.md`.
- LibreOffice / Electron apps
- Cursor theme (set once, not swapped per theme)
- Per-theme fonts (all shipped themes use JetBrains Mono Nerd Font)
- **No keybinding for `dot-theme-toggle`.** The Hyprland-era `$mod+Shift+T`
  went with Hyprland; nothing is bound under EWM.
```

Also fix the stale `$mod+Shift+T` reference in the "Commands" block at the top
of the chapter — that binding no longer exists.

- [ ] **Step 5: Update the "Adding a new theme" section**

```markdown
## Adding a new theme

Themes are generated from `lib/themes.nix`, so adding one is two steps:

1. Add a palette to `palettes` in `lib/themes.nix` (26 slots; copy an existing
   one as the shape).
2. Render its directory and check contrast:

```bash
cd ~/dotfiles
PAL=$(mktemp)
nix eval --json --impure --expr 'let t = import ./lib/themes.nix { pkgs = import <nixpkgs> {}; };
  in builtins.mapAttrs (n: p: p // { ansi = t.ansiSlots p; }) t.palettes' > "$PAL"
bin/gen-theme-dir.py <new-theme> themes/<new-theme> themes/catppuccin-mocha/btop.theme < "$PAL"
echo <emacs-theme-name> > themes/<new-theme>/emacs-theme
python3 tests/contrast-check.py < "$PAL"
```

Then rebuild (so Nix renders its ghostty config) and apply:

```bash
sudo nixos-rebuild switch --flake .#<host>
dot-theme-set <new-theme>
```

No code changes needed — `dot-theme-set` discovers themes via `ls themes/`,
and Emacs resolves the theme through `themes/<name>/emacs-theme`.
```

- [ ] **Step 6: Verify no stale claims remain**

```bash
cd ~/dotfiles
grep -n "mod+Shift+T\|ghostty.conf\|catppuccin flavor\|Only two apps" docs/manual/02-theming.md \
  || echo "no stale references"
grep -n "Firefox" docs/manual/02-theming.md | head -3
```

- [ ] **Step 7: Commit**

```bash
git add docs/manual/02-theming.md
git commit -m "docs(theming): four themes, generated directories, new surfaces

Rewrites chapter 02 for the high-contrast work: the four shipped themes with
their measured contrast, the generated-not-hand-written theme directories,
the emacs-theme file, and the zellij/Claude/Firefox additions to the switch
sequence.

Corrects three claims that were already stale before this work: the
\$mod+Shift+T binding went with Hyprland, ghostty.conf no longer lives in the
theme directory, and 'only two apps are themed by file symlink' has not been
true since pi and GTK were added."
```

---

## Task 9: Live verification on rafik

**OPERATIONAL — Scott runs this.** It needs a live EWM session and `sudo`. An
agent's job is to prepare the commands, check pasted-back output, and stop.

The theme system has **never actually run on rafik** — `~/.config/dotfiles/`
does not exist there. This task is the first real exercise of it.

- [ ] **Step 1: Get rafik current and rebuild**

```bash
cd ~/dotfiles
git pull --ff-only origin main
sudo nixos-rebuild switch --flake .#rafik
```

- [ ] **Step 2: Confirm the pre-switch state**

```bash
ls ~/.config/ghostty/themes/
readlink ~/.config/ghostty/theme.conf
cat ~/.config/dotfiles/active-theme 2>/dev/null || echo "no active-theme yet (expected on first run)"
```

Expected: four `.conf` files; `theme.conf` pointing at one of them (the
activation hook seeded it); no `active-theme` marker yet.

- [ ] **Step 3: Switch to high contrast**

```bash
dot-theme-set high-contrast-dark
```

Expected final line: `Switched to high-contrast-dark (dark)`

- [ ] **Step 4: Verify Emacs actually changed — by query, not by eye**

```bash
emacsclient -e '(list :enabled custom-enabled-themes :bg-fg (modus-themes-with-colors (list bg-main fg-main)))'
```

Expected exactly: `(:enabled (modus-vivendi) :bg-fg ("#0a0a0a" "#e8e8e8"))`

If `custom-enabled-themes` is `(catppuccin)`, the emacsclient handoff did not
land. If bg/fg read `("#000000" "#ffffff")`, the Modus overrides are not
applying.

- [ ] **Step 5: Verify the other surfaces**

```bash
readlink ~/.config/ghostty/theme.conf          # → themes/high-contrast-dark.conf
readlink ~/.local/share/dotfiles/zellij-themes/active/theme.kdl  # → available/eminix-dark.kdl
python3 -c "import json;print(json.load(open('$HOME/.claude/settings.json'))['theme'])"   # → dark-ansi
gsettings get org.gnome.desktop.interface color-scheme      # → 'prefer-dark'
```

- [ ] **Step 6: The regression this whole design exists to prevent**

Order matters — switch first, **then** rebuild:

```bash
sudo nixos-rebuild switch --flake .#rafik
readlink ~/.config/ghostty/theme.conf
ls ~/.config/ghostty/*.hm-bak 2>/dev/null || echo "no hm-bak — correct"
```

Expected: `theme.conf` still points at `high-contrast-dark.conf`, and **no
`.hm-bak` file exists**. If `theme.conf` reverted or a `.hm-bak` appeared,
Task 3 did not take.

- [ ] **Step 7: Toggle round-trip leaves the repo clean**

```bash
dot-theme-toggle && cat ~/.config/dotfiles/active-theme
dot-theme-toggle && cat ~/.config/dotfiles/active-theme
cd ~/dotfiles && git status --porcelain
```

Expected: flips to a light theme and back to `high-contrast-dark`. `git status`
shows **only** `ioshi/i-intelligence/claude/settings.json` (the documented
exception). Anything else means something wrote into the checkout.

- [ ] **Step 8: The ssh case**

From rafik:

```bash
ssh whistle
# inside the session:
zellij attach --create main    # should render in rafik's palette
claude                          # should render in rafik's palette
```

Both should look like rafik's active theme, because both read the terminal's
ANSI colours and that terminal is rafik's ghostty.

- [ ] **Step 9: Live-reload behaviour of zellij (open question)**

The spec flags this as unverified. Determine which is true:

```bash
dot-theme-toggle
# Does the running zellij change? If not:
zellij kill-session main && zellij attach --create main
```

Record the answer in `docs/manual/02-theming.md` — either "zellij picks up
theme changes live" or "zellij needs a detach/attach". Do not guess.

---

## Self-Review Notes

**Spec coverage.** Every item in the spec's "Repo changes" table maps to a
task: `lib/themes.nix` → Tasks 1 and 5; `ghostty.nix` → Task 3; `firefox.nix`
→ Task 5; `scott-theme.el` → Task 4; `zellij/config.kdl` → Task 6;
`claude/settings.json` → Task 7; `dot-theme-set` → Tasks 3, 4, 6, 7;
`themes/high-contrast-*` → Task 2; `themes/*/emacs-theme` → Task 4;
`themes/*/ghostty.conf` deletion → Task 2; `docs/manual/02-theming.md` →
Task 8. All five spec verification items appear in Task 9.

**Two additions the spec did not name**, both forced by inspection during
planning:
- `bin/gen-pi-theme.py` reads a hardcoded `toml["catppuccin"]`, so a
  non-Catppuccin theme could not produce a pi theme. Handled in Task 2.
- `btop.theme` has 42 entries drawn from 17 palette slots and no generator
  existed. Rather than hand-write two more, Task 2's generator substitutes by
  slot — and is verified by reproducing the committed Catppuccin file
  byte-for-byte.

**Naming consistency.** `scott/theme-set` takes a theme *name* everywhere
(Task 4 defines it; Tasks 4 and 9 call it). Theme directory names
(`high-contrast-dark`) match palette attribute names in `lib/themes.nix`
exactly — `dot-theme-set` and `ghostty.nix` both index by that string, so a
mismatch breaks both.

**Deliberately not verified from the desk:** whether zellij hot-reloads a
theme file. Task 9 step 9 determines it on the machine rather than asserting
it here.
