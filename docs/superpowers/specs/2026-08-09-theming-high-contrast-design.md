# eminix theming — high-contrast variants and full-surface coverage

**Date:** 2026-08-09
**Status:** approved (design), not yet implemented
**Prior art:** `docs/manual/02-theming.md` (the system as built), `2026-08-07-eminix-convergence-design.md`

## Goal

Add a high-contrast dark/light pair to the eminix theme system, and extend the
system to cover the surfaces it currently misses — Emacs beyond Catppuccin,
Firefox chrome, zellij, and Claude Code — so that switching to high contrast
actually changes every pixel Scott looks at.

## Why this exists

Scott has visual snow syndrome. High contrast is a genuine accessibility need,
not a preference. That has three consequences the design has to respect:

- **Catppuccin is the wrong palette for this.** It is a deliberately soft,
  pastel scheme; low contrast is its design intent. Measured against WCAG
  (2026-08-09):

  | palette | text/base | subtext0/base | overlay0/base | blue/base |
  |---|---|---|---|---|
  | `catppuccin-mocha` | 11.34 AAA | 7.37 AAA | **3.36 fail** | 7.79 AAA |
  | `catppuccin-latte` | 7.06 AAA | **4.37 fail** | **2.30 fail** | **4.34 fail** |

  Latte fails AA in three of four sampled pairs. The light theme is the weaker
  one, which is backwards from what a light-sensitive user needs.

- **Maximum contrast is not the target.** Pure `#fff` on `#000` (21:1) commonly
  produces halation — text appearing to glow or smear — which is frequently
  worse for visual snow than a slightly softened pair. Pure white backgrounds
  are also the usual photophobia trigger. The peak of the contrast scale and
  the most readable point are not the same place.

- **Coverage matters more than fidelity.** A theme that repaints the terminal
  but leaves the editor untouched is not a high-contrast mode. Under EWM, Emacs
  *is* the screen.

## Facts on the ground (verified 2026-08-09)

Each of these was confirmed by inspection or execution, not assumed. Several
invalidate what the code's own comments claim.

1. **The Emacs layer is hard-wired to Catppuccin.** `scott-theme.el` does
   `(require 'catppuccin-theme)`, and `scott/theme-set` takes a *flavor*
   (`"mocha"`/`"latte"`) and sets `catppuccin-flavor`. Startup derives it with
   `(if (string-match-p "latte" name) 'latte 'mocha)` — any theme name lacking
   "latte" silently becomes Mocha. A `high-contrast-dark` theme cannot be
   expressed at all.

2. **`dot-theme-set` never passes the theme name to Emacs.** It derives the
   flavor from the *variant* only:
   ```bash
   emacs_flavor="mocha"
   [[ "$VARIANT" == "light" ]] && emacs_flavor="latte"
   ```

3. **The Emacs handoff has never worked on rafik.** `dot-theme-set` hardcodes
   `EMACSCLIENT="$HOME/.nix-profile/bin/emacsclient"`. That path does not exist
   on rafik; the EWM build's client is `/run/current-system/sw/bin/emacsclient`.
   The call is wrapped in `|| true`, so it has been failing silently on the only
   EWM host.

4. **The runtime switcher has never run on rafik.** `~/.config/dotfiles/` does
   not exist there, so there is no `active-theme` marker. The whole
   directory-per-theme mechanism is effectively untested on the machine it
   matters most for.

5. **Ghostty's `theme.conf` has two owners.** `ghostty.nix` declares
   `home.file.".config/ghostty/theme.conf"` while `dot-theme-set` does
   `ln -sfn "$THEME_DIR/ghostty.conf"` over the same path. Home Manager wins at
   every activation, renaming the runtime symlink to `theme.conf.hm-bak`. The
   first theme switch would therefore be reverted by the next
   `nixos-rebuild switch`. `ghostty.nix` already carries the comment
   *"Pre-generate all theme variants so the runtime switcher can flip symlinks"*,
   so the `theme.conf` declaration contradicts its own stated design.

6. **Modus themes ship with Emacs 30.2** at
   `share/emacs/30.2/etc/themes/` — no package needed. But they are 19–21:1 out
   of the box (`modus-vivendi` is `#000000`/`#ffffff`; `modus-vivendi-tinted` is
   `#0d0e1c`/`#ffffff`), i.e. exactly the halation case being avoided. They need
   palette overrides, not raw use.

7. **Zellij 0.44.3 accepts bare ANSI colour indices.** A theme written as
   `fg 15` / `bg 0` passes `zellij setup --check` with
   `[CONFIG FILE]: Well defined.` Indices 0–15 resolve against the *terminal's*
   palette at render time.

8. **Claude Code has `-ansi` theme variants** which take their colours from the
   terminal palette rather than Claude's built-ins.

9. **Two config paths are live symlinks into the checkout.** `~/.config/zellij`
   (`zellij.nix`) and `~/.claude/settings.json` (`claude.nix`) both use
   `mkOutOfStoreSymlink` into `$DOTFILES`. Anything written there at runtime
   dirties the working tree — the "Helix drift caveat" recorded in
   `docs/manual/02-theming.md`.

10. **Under ssh, the terminal belongs to the *client*.** Scott runs Claude Code
    on whistle either locally (WSLg ghostty) or ssh'd from rafik. In the ssh
    case the rendering terminal is rafik's ghostty. Any per-host hardcoded
    colours on whistle would clash with rafik's palette.

## Decisions (with rationale)

1. **Four themes, not two.** Keep `catppuccin-mocha` and `catppuccin-latte`;
   add `high-contrast-dark` and `high-contrast-light`. `dot-theme-toggle`
   continues to flip dark↔light within the last-used theme of each variant;
   choosing high contrast is an explicit `dot-theme-set`. Rejected: replacing
   Catppuccin outright (removes a working option for no gain), and recolouring
   Catppuccin in place (loses its visual identity and still gives only one
   contrast level).

2. **Softened near-maximum, ~16:1 — not 21:1.** `high-contrast-dark` is
   `#0a0a0a`/`#e8e8e8` (16.16:1); `high-contrast-light` is `#f2f2f2`/`#111111`
   (16.87:1). Both are far above AAA (7:1) and both current themes, while
   avoiding halation and large pure-white surfaces. Every accent slot is tuned
   to clear 7:1 against its own base — see Palettes below.

3. **Firefox: chrome only, no content override.** `userChrome.css` themes the
   browser UI; page colours are left exactly as authored. Rejected for now:
   `browser.display.document_color_use = 2`, which forces the palette onto every
   page and triggers `forced-colors: active`. It is the single biggest
   accessibility lever available — page content is the overwhelming majority of
   the window, and chrome is under 10% — but it breaks sites that hardcode
   colours without honouring the media query. **Recorded as a one-pref extension
   point**: adding that single pref to the high-contrast themes' Firefox config
   turns it on later without touching anything else in this design.

4. **Emacs themes become data, not a hardcoded flavor.** Each theme directory
   gains an `emacs-theme` file naming the Emacs theme to load, and
   `scott/theme-set` takes that name instead of a Catppuccin flavor. This
   matches the existing "directory-per-theme, all files pre-rendered, no
   templating" philosophy: adding a theme stays a directory copy with no code
   change. Catppuccin themes name `catppuccin`; high-contrast themes name
   `modus-vivendi`/`modus-operandi`.

5. **Modus with palette overrides, not raw Modus and not a hand-rolled theme.**
   `modus-themes-common-palette-overrides` pins `bg-main`/`fg-main` to the
   palette's `base`/`text`, so the Emacs surface matches decision 2 rather than
   Modus's default 19–21:1. This keeps Protesilaos's accessibility-tuned
   semantic colours — the genuinely hard part — while honouring the chosen
   contrast. Rejected: writing a theme from the palette by hand (large surface
   area, permanent maintenance, worse accessibility than Modus).

6. **Home Manager stops owning `~/.config/ghostty/theme.conf`.** Build time
   pre-renders every variant into `~/.config/ghostty/themes/<name>.conf`;
   runtime owns the `theme.conf` symlink and points it at one of those. A
   `home.activation` hook seeds the symlink only when absent, so a fresh machine
   has a theme before the first switch without Home Manager claiming the path.
   `themes/<name>/ghostty.conf` is then deleted as duplicated state — the Nix
   palette becomes the single source.

7. **Zellij and Claude Code follow the terminal, and switch on variant only.**
   Both are terminal applications, and under ssh the terminal is rafik's
   ghostty. Neither gets hardcoded palette colours. Zellij gets two
   ANSI-index-based themes; Claude Code gets `dark-ansi`/`light-ansi`. Because
   `dot-theme-set` already repaints ghostty's 16 ANSI slots, both inherit
   high contrast automatically, over ssh, with no per-host state. Switching
   *palette* requires no change to either; only dark↔light does.

8. **Nothing writes into the checkout at runtime.** Zellij's theme file lives
   outside the repo (`theme_dir` set to a non-repo path, `theme "active"` in the
   committed `config.kdl`, and `dot-theme-set` flips `<theme_dir>/active.kdl`).
   This is the one place the design deliberately diverges from an existing
   pattern: `~/.claude/settings.json` already accepts a dirty tree as a
   documented trade-off, and the Claude theme key joins that, but zellij does
   not need to and should not.

## Architecture

The existing split is correct and is kept; three places break its contract and
are fixed rather than worked around.

```
BUILD TIME (Nix)                          RUNTIME (dot-theme-set)
lib/themes.nix                            ~/.config/dotfiles/active-theme
  palettes.<name> ──┐                       last-dark / last-light
                    ├─ generators ──▶ pre-rendered variants ──▶ flip symlinks
  4 palettes        │  ghostty              in per-app theme dirs    notify apps
                    │  swaylock                                      write state
                    └─ (firefox userChrome)
```

**Contract:** Nix renders *every* theme for *every* app at build time; the
runtime switcher only selects among them and notifies running processes. The
switcher never generates config, and never writes inside the repo.

## Components

Each surface, what it needs, and how it learns the active theme.

| Surface | Mechanism | Switch cost |
|---|---|---|
| ghostty | HM pre-renders 4 `themes/<name>.conf`; runtime flips `theme.conf`; `SIGUSR2` reload | live |
| Emacs | `emacs-theme` file per theme dir → `scott/theme-set <name>` via emacsclient | live |
| btop | existing symlink flip | live |
| GTK | existing `gsettings color-scheme` / `gtk-theme` | live |
| pi agent | existing `gen-pi-theme.py` from `colors.toml` | live (file watch) |
| Firefox chrome | per-theme `userChrome.css` + `toolkit.legacyUserProfileCustomizations.stylesheets` | restart (dark/light axis is live via gsettings) |
| zellij | 2 ANSI-index themes; flip `<theme_dir>/active.kdl` | verify — may need detach/attach |
| Claude Code | `theme` key = `dark-ansi`/`light-ansi` in settings.json | next start |

**Emacs theme mapping** (`themes/<name>/emacs-theme`):

| theme | contents |
|---|---|
| `catppuccin-mocha` | `catppuccin` |
| `catppuccin-latte` | `catppuccin` |
| `high-contrast-dark` | `modus-vivendi` |
| `high-contrast-light` | `modus-operandi` |

Catppuccin still needs its flavor set, so `scott/theme-set` keeps flavor
handling for the `catppuccin` case and uses `load-theme` for everything else.
The `variant` file already distinguishes mocha from latte.

## Palettes

Both palettes are full 26-slot sets, so every existing generator works
unchanged. Values are tuned so that **every accent clears 7:1 (AAA) against its
own base** — verified 2026-08-09.

`high-contrast-dark` (variant `dark`) — text/base **16.16:1**, lowest accent
`overlay0` at **7.12:1**:

```
rosewater #ffd7d0  flamingo #ffb3a7  pink     #ff9ee0  mauve    #c9a3ff
red       #ff6b6b  maroon   #ff8f8f  peach    #ffb060  yellow   #ffd93d
green     #5ee06a  teal     #4fe0c8  sky      #5fd7ff  sapphire #4cc8f0
blue      #7ab8ff  lavender #b9c4ff  text     #e8e8e8  subtext1 #dcdcdc
subtext0  #cfcfcf  overlay2 #b2b2b2  overlay1 #9e9e9e  overlay0 #9b9b9b
surface2  #3d3d3d  surface1 #2e2e2e  surface0 #1f1f1f  base     #0a0a0a
mantle    #050505  crust    #000000
```

`high-contrast-light` (variant `light`) — text/base **16.87:1**, lowest accent
`red` at **7.06:1**:

```
rosewater #8a3324  flamingo #95291e  pink     #9d006b  mauve    #6b21a8
red       #a70019  maroon   #96001a  peach    #804000  yellow   #654d00
green     #0d5e1b  teal     #005a56  sky      #005776  sapphire #00567a
blue      #0043a8  lavender #3b3ba8  text     #111111  subtext1 #212121
subtext0  #2e2e2e  overlay2 #3a3a3a  overlay1 #4a4a4a  overlay0 #515151
surface2  #b0b0b0  surface1 #c4c4c4  surface0 #d6d6d6  base     #f2f2f2
mantle    #e8e8e8  crust    #dedede
```

For comparison, `overlay0` — the slot both Catppuccin themes fail worst — goes
from 3.36:1 (mocha) and 2.30:1 (latte) to **7.12:1** and **7.09:1** here. That
slot is used for dimmed and secondary text, so it is precisely the one where
Catppuccin's softness costs the most legibility.

## Repo changes

| File | Change |
|---|---|
| `lib/themes.nix` | **Add** two palettes; **delete** the dead `hyprland` and `mako` generators (both modules were removed in the convergence); **add** a `firefoxChrome` generator |
| `ioshi/i-intelligence/ghostty.nix` | **Remove** `home.file.".config/ghostty/theme.conf"`; pre-render all four into `themes/`; add the seeding activation hook |
| `ioshi/i-intelligence/firefox.nix` | **Add** per-theme `userChrome.css` + `toolkit.legacyUserProfileCustomizations.stylesheets = true` |
| `ioshi/i-intelligence/emacs/lisp/scott-theme.el` | **Rewrite** to take a theme name; add Modus palette overrides; keep Catppuccin flavor handling |
| `ioshi/i-intelligence/zellij/config.kdl` | **Add** `theme_dir` (non-repo) + `theme "active"`; **add** the two ANSI-index theme definitions |
| `ioshi/i-intelligence/claude/settings.json` | **Add** `theme` key |
| `bin/dot-theme-set` | **Fix** the emacsclient path; pass theme *name*; flip ghostty from `~/.config/ghostty/themes/`; write zellij + Claude theme state |
| `themes/high-contrast-{dark,light}/` | **Create**, mirroring the existing anatomy |
| `themes/*/emacs-theme` | **Create** for all four |
| `themes/*/ghostty.conf` | **Delete** — superseded by the Nix-rendered variants |
| `docs/manual/02-theming.md` | **Update**: four themes, the new files, and remove Firefox from "not handled" |

## Verification

The system has never actually been exercised on rafik, so verification is part
of the work, not an afterthought.

1. `dot-theme-set high-contrast-dark` on rafik, then confirm — by query, not by
   eye — that Emacs reports the expected theme
   (`custom-enabled-themes` = `(modus-vivendi)`), that `bg-main` equals
   `#0a0a0a`, and that `~/.config/dotfiles/active-theme` was written.
2. `nixos-rebuild switch` immediately afterwards, then re-check the ghostty
   symlink still points where the switcher put it. This is the regression that
   decision 6 exists to prevent, and it must be tested in that order.
3. `dot-theme-toggle` round-trips dark↔light and back, leaving
   `git status` clean in `~/dotfiles`.
4. ssh from rafik into whistle and confirm zellij and Claude Code render in the
   client's palette.
5. All three hosts build; whistle and datacore closures should be unchanged
   except where they genuinely consume the new files.

## Out of scope

- **Firefox content colours** — decision 3, with the exact pref recorded so it
  can be enabled later.
- **A keybinding for `dot-theme-toggle`.** The Hyprland-era `$mod+Shift+T` is
  gone with Hyprland, and binding anything under EWM is Scott's call — he names
  the key.
- **Per-theme fonts**, LibreOffice, and Electron apps other than the ones
  listed. Unchanged from the current manual's omissions list.
- **The `s`/gdocs and ssh-config items** noted during the 2026-08-09 rafik
  investigation — unrelated to theming, already resolved or recorded separately.
