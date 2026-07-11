# Emacs-Centric Workflow on Nix — Design

> **Date:** 2026-07-07
> **Status:** Approved design, pre-implementation
> **Relates to:** `docs/manual/07-nix-roadmap.md` (Nix Phase 1/2 migration plan)

## Summary

Adopt Emacs as the daily driver for file navigation, text editing, light programming,
the pi agent, the weather surface (`super+n`), the OpenRouter cost surface (`super+u`),
and — the big one — as the replacement for Obsidian via org-mode. The Emacs config is
built as Nix from day one: it becomes the **pilot Home Manager module** of the Nix
Phase 1 migration, proving the HM workflow before the existing stow packages migrate.

## Decisions (settled during brainstorming)

| Question | Decision |
|---|---|
| Vault format | **Convert to org-mode** (one-way; mobile becomes read-mostly, accepted tradeoff) |
| Emacs config style | **Hand-rolled init.el, packages declared in Nix** via emacs-overlay — no second package manager |
| Sequencing vs Nix migration | **Emacs is the pilot HM module**; roadmap beat order resumes after |
| Editing paradigm | **Meow** — modal, selection-first, closest to Helix muscle memory |
| Weather / OpenRouter / pi surfaces | **Native elisp rewrites** rendering into Emacs buffers; pi in vterm |

## 1. Position in the migration

Roadmap steps 1–2 (install Nix daemon, bootstrap standalone Home Manager on Debian)
happen first, unchanged. Then `modules/home-manager/emacs.nix` is the first real module
deployed — chosen because it has no stow package to displace, so it proves the HM
workflow with zero conflict risk. The existing beat order (git → zsh → helix → …)
resumes afterward. `helix.nix` and `lf.nix` stay in the module plan as fallbacks and
are dropped only once Emacs is proven as daily driver.

## 2. Architecture

- **Flake input:** `emacs-overlay` (nix-community) added to `flake.nix`.
- **Build:** `emacs-pgtk` — native Wayland, correct for Hyprland.
- **Packages:** declared in `emacs.nix` via `programs.emacs.extraPackages`. No
  elpaca/straight/package.el installs at runtime. Adding a package = edit the module,
  `home-manager switch`.
- **Config:** real elisp files in the repo (`modules/home-manager/emacs/init.el` +
  `lisp/*.el`), linked into `~/.config/emacs` with `mkOutOfStoreSymlink` during
  Phase 1 so elisp iterates live without a rebuild. Packages stay declarative; only
  config text is live-editable. Can be tightened to pure store paths later.
- **Daemon:** `services.emacs.enable = true` — HM manages the systemd user service.
  All entry points are `emacsclient` frames, so everything (including `super+n`)
  opens instantly.

## 3. Core package set by role

| Role | Replaces | Packages |
|---|---|---|
| Modal editing | Helix keybinds | meow |
| File navigation | lf | dired + dirvish |
| Minibuffer/search | fuzzel-ish fuzzy everything | vertico, orderless, consult, marginalia, embark |
| In-buffer completion | — | corfu |
| Git | CLI git | magit |
| Light programming | Helix LSP | built-in treesit modes + eglot |
| Knowledge base | Obsidian | org, org-roam, org-agenda |
| Terminal / pi agent | ghostty tab | vterm |
| Theme | — | catppuccin-theme (mocha + latte built in) |
| Markdown (transition) | — | markdown-mode, until vault conversion completes |

## 4. Theme integration

`catppuccin-theme` for Emacs already implements the exact palettes, so
`lib/themes.nix` needs no Emacs generator — the HM module sets the flavor from the
theme parameter. Runtime toggling: `dot-theme-set` gains one line,
`emacsclient -e '(scott/theme-set "latte")'`, preserving the sub-second toggle.
The Obsidian JSON-patch block in `dot-theme-set` is removed when Obsidian is retired.

## 5. Surfaces (native elisp)

- **`scott/weather`** (`super+n` → `emacsclient -e`): fetches the NWS hourly forecast
  for Phoenix, NY with `url.el`, renders the same 8-period table (time, temp, precip
  probability, short forecast) into a popup buffer, and displays the NOAA
  satellite/radar images inline via `image-mode` — mpv exits this job. A Hyprland
  windowrule floats the frame as today.
- **`scott/openrouter-cost`** (`super+u`): reads keys from `~/.pi/agent/auth.json`
  (management + regular key), hits the OpenRouter activity + key APIs, renders the
  rolling 7-day cost table in a buffer instead of a notification.
- **Pi agent:** a toggle command opening pi in a dedicated vterm buffer. Pi stays
  npm-installed (as the Nix roadmap already accepts); Emacs is just its house.
- The bash `hypr-weather` / `hypr-or-cost` scripts stay in `base/bin` until the elisp
  versions are verified working, then are removed along with their keybind lines.

## 6. Vault conversion — its own sub-project

A **one-way door**; gets its own spec and plan, executed only after Emacs is the
comfortable daily driver. Shape:

1. Snapshot the vault (git commit + full copy outside the sync tree)
2. Batch-convert `.md` → `.org` (pandoc-based script + wikilink → org-roam ID rewriting)
3. Build the org-roam DB
4. Run a link-integrity check (every former wikilink resolves to a node)
5. Only then retire Obsidian from the install flow and `dot-doctor`

Syncthing is untouched — org files sync like any text. Mobile becomes read-mostly
(accepted tradeoff; Orgzly is a later option).

## 7. Sequencing summary

1. Nix daemon + HM bootstrap (roadmap steps 1–2, unchanged)
2. `emacs.nix` pilot: meow + vertico stack + dired + magit + org — minimal but livable
3. Daily-drive editing/file-nav in Emacs; Helix/lf remain as escape hatches
4. Surfaces: weather, openrouter-cost, pi vterm; swap the three Hyprland binds
5. Resume roadmap beat order (git → zsh → …) for the stow migration
6. Vault conversion sub-project (separate spec)
7. Drop helix/lf/obsidian from the config; update manual chapters

**Testing/safety:** `nix flake check` before every switch; `dot-doctor` gains checks
for the Emacs daemon and org-roam DB; every step is individually reversible except
step 6, which is why it is last and separately planned.

## 8. Future direction — EWM (deferred, capture only)

**What:** [EWM](https://codeberg.org/ezemtsov/ewm/) — a Wayland compositor
(Rust/Smithay) running as an Emacs dynamic module; every app window is an Emacs buffer.

**Why it's the logical endgame:** it collapses the desktop stack into the tool this
design already makes central. Hyprland, fuzzel (→ minibuffer), the window-picker Rust
tool, and possibly waybar (→ modeline/tab-bar) all become Emacs concerns. One config
language, one theme target, one keybinding system — the same unification argument as
the Nix migration itself, applied to the desktop.

**Prerequisites before attempting:**

1. Emacs is the proven daily driver (steps 2–4 complete, months of fluency)
2. Vault conversion done — Emacs already the center of gravity
3. Ideally on NixOS (Phase 2), since EWM ships a Nix flake and a compositor swap is
   cleanest when the system layer is declarative too

**Design impact today:** none structurally — but it reinforces two choices already
made: keep the Emacs config hand-rolled and Nix-managed (EWM's flake composes with
ours), and invest in Emacs-native surfaces rather than Hyprland-side scripts — every
elisp surface built now survives a compositor swap; every Hyprland bind dies with it.
Slots in as a possible **Phase 3** after the NixOS cutover, with its own spec when
the time comes.

**Fallback story:** Hyprland's HM module stays in the flake even if EWM is adopted —
booting into either is a session choice, not a rebuild, so it's fully reversible.

**Known EWM caveats (as of 2026-07):** young project; must launch from a TTY (no
nested mode); automatic GPU selection with no override; some Wayland protocol
features incomplete.

## Out of scope

- The stow → HM migration details for existing packages (already specified in
  `docs/manual/07-nix-roadmap.md`)
- NixOS Phase 2 cutover
- Vault conversion mechanics (future spec)
- EWM adoption (future spec)
