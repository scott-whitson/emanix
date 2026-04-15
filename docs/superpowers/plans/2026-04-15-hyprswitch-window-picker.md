# Hyprswitch Window Picker Implementation Plan

> **Status: ABANDONED.** Tasks 1–5 were executed, then reverted after live testing revealed hyprswitch's modal-picker UX did not match the intended per-window ace-jump overlay. Superseded by the custom overlay tool plan. Kept for history.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `Super+Tab` window picker to Hyprland that labels each visible window with a digit (1–9, 0) and focuses the chosen window on keypress.

**Architecture:** Use the AUR package `hyprswitch` (Rust + GTK4 + gtk4-layer-shell). Run its `init` daemon at Hyprland startup; bind `Super+Tab` to `hyprswitch gui` with `--close default --max-switch-offset 10`. Provide themed CSS (dark.css / light.css) swapped by the existing `theme-switch` script, which must restart the daemon because hyprswitch has no CSS hot-reload.

**Tech Stack:** Hyprland, hyprswitch v4+, GTK4 CSS, bash, GNU stow.

**Design spec:** `docs/superpowers/specs/2026-04-15-hyprswitch-window-picker-design.md`

---

## File Map

**New files:**
- `base/hyprswitch/.config/hyprswitch/dark.css` — dark-theme styling for the picker overlay.
- `base/hyprswitch/.config/hyprswitch/light.css` — light-theme styling.

**Modified files:**
- `base/hypr/.config/hypr/hyprland.conf` — adds one `exec-once` line and one `bind` line.
- `base/bin/.local/bin/theme-switch` — adds one symlink line and one daemon-restart line.
- `README.md` — documents the new `Super+Tab` binding and the one-time `paru -S hyprswitch` install.

**Runtime-only (not committed, like waybar):**
- `~/.config/hyprswitch/style.css` — symlink pointing to the active `{dark,light}.css`, managed by `theme-switch`.

**Known CSS selectors (from hyprswitch's `test.css` reference):** `.monitor`, `.monitor_active`, `.workspace`, `.workspace_active`, `.workspace_special`, `.client`, `.client_active`, `.client-image`, `.index`. The CSS variable `--border-size` is provided by hyprswitch.

---

## Task 1: Install hyprswitch from AUR

**Files:** none (system package).

- [ ] **Step 1: Verify paru is installed**

Run: `command -v paru && paru --version`
Expected: prints a path and a version like `paru v2.0.x`.

If `paru` is not installed, stop and report — paru bootstrap is outside this plan.

- [ ] **Step 2: Install hyprswitch**

Run: `paru -S --needed hyprswitch`
Expected: package installs (or "is up to date"); exit code 0.

- [ ] **Step 3: Verify the binary works**

Run: `hyprswitch --version`
Expected: version string printed, exit code 0.

(No commit — this is a system-level action, not a repo change.)

---

## Task 2: Create hyprswitch stow package with dark.css

**Files:**
- Create: `base/hyprswitch/.config/hyprswitch/dark.css`

- [ ] **Step 1: Create the directory**

Run: `mkdir -p base/hyprswitch/.config/hyprswitch`
Expected: directory exists, no error.

- [ ] **Step 2: Write dark.css**

Create `base/hyprswitch/.config/hyprswitch/dark.css` with exactly this content:

```css
/* Tokyo Night — dark variant. Keep in sync with base/hypr/.config/hypr/colors/dark.conf. */

* {
    color: #c0caf5;
    font-family: "JetBrains Mono", monospace;
    font-weight: 600;
}

window {
    background: rgba(26, 27, 38, 0.85);
}

.monitor {
    background: rgba(36, 40, 59, 0.6);
    border-radius: 8px;
    padding: 8px;
    margin: 6px;
}

.monitor_active {
    border: var(--border-size) solid #7aa2f7;
}

.workspace {
    background: rgba(41, 46, 66, 0.6);
    border-radius: 6px;
    padding: 6px;
    margin: 4px;
}

.workspace_active {
    border: var(--border-size) solid #7aa2f7;
}

.workspace_special {
    border: var(--border-size) solid #bb9af7;
}

.client {
    background: #24283b;
    border: var(--border-size) solid #414868;
    border-radius: 4px;
    padding: 4px;
    margin: 3px;
}

.client_active {
    border: var(--border-size) solid #7aa2f7;
}

.client-image {
    background: transparent;
}

.index {
    background: #7aa2f7;
    color: #1a1b26;
    font-size: 18px;
    font-weight: 700;
    border-radius: 4px;
    padding: 2px 8px;
    margin: 4px;
}
```

- [ ] **Step 3: Verify the file is valid**

Run: `cat base/hyprswitch/.config/hyprswitch/dark.css | head -3`
Expected: prints the comment and the `*` selector.

- [ ] **Step 4: Commit**

```bash
git add base/hyprswitch/.config/hyprswitch/dark.css
git commit -m "hyprswitch: add dark-theme stylesheet"
```

---

## Task 3: Add light.css variant

**Files:**
- Create: `base/hyprswitch/.config/hyprswitch/light.css`

- [ ] **Step 1: Write light.css**

Create `base/hyprswitch/.config/hyprswitch/light.css` with exactly this content:

```css
/* Tokyo Night Day — light variant. Keep in sync with base/hypr/.config/hypr/colors/light.conf. */

* {
    color: #3760bf;
    font-family: "JetBrains Mono", monospace;
    font-weight: 600;
}

window {
    background: rgba(224, 224, 229, 0.9);
}

.monitor {
    background: rgba(200, 204, 213, 0.7);
    border-radius: 8px;
    padding: 8px;
    margin: 6px;
}

.monitor_active {
    border: var(--border-size) solid #2e7de9;
}

.workspace {
    background: rgba(210, 214, 223, 0.7);
    border-radius: 6px;
    padding: 6px;
    margin: 4px;
}

.workspace_active {
    border: var(--border-size) solid #2e7de9;
}

.workspace_special {
    border: var(--border-size) solid #9854f1;
}

.client {
    background: #e1e2e7;
    border: var(--border-size) solid #a8aecb;
    border-radius: 4px;
    padding: 4px;
    margin: 3px;
}

.client_active {
    border: var(--border-size) solid #2e7de9;
}

.client-image {
    background: transparent;
}

.index {
    background: #2e7de9;
    color: #e1e2e7;
    font-size: 18px;
    font-weight: 700;
    border-radius: 4px;
    padding: 2px 8px;
    margin: 4px;
}
```

- [ ] **Step 2: Commit**

```bash
git add base/hyprswitch/.config/hyprswitch/light.css
git commit -m "hyprswitch: add light-theme stylesheet"
```

---

## Task 4: Stow the hyprswitch package

**Files:** none — this is a stow operation.

- [ ] **Step 1: Stow the new package**

Run: `cd ~/dotfiles && stow -d base -t "$HOME" --no-folding hyprswitch`
Expected: no output (success) or no conflict message.

- [ ] **Step 2: Verify the symlinks exist**

Run: `ls -la ~/.config/hyprswitch/`
Expected: `dark.css` and `light.css` present as symlinks pointing into `~/dotfiles/base/hyprswitch/.config/hyprswitch/`.

(No commit — stow creates symlinks outside the repo.)

---

## Task 5: Extend theme-switch to manage the hyprswitch symlink and daemon

**Files:**
- Modify: `base/bin/.local/bin/theme-switch`

- [ ] **Step 1: Add the symlink line**

Find the existing symlink block in `base/bin/.local/bin/theme-switch` (around lines 31-34):

```bash
# --- Swap symlinks (relative so they resolve within each config dir) ---
ln -sf "$target.conf" "$CONFIG/hypr/colors/theme.conf"
ln -sf "$target.conf" "$CONFIG/ghostty/theme.conf"
ln -sf "$target.css"  "$CONFIG/waybar/style.css"
```

Add a new line for hyprswitch immediately after the waybar line:

```bash
# --- Swap symlinks (relative so they resolve within each config dir) ---
ln -sf "$target.conf" "$CONFIG/hypr/colors/theme.conf"
ln -sf "$target.conf" "$CONFIG/ghostty/theme.conf"
ln -sf "$target.css"  "$CONFIG/waybar/style.css"
ln -sf "$target.css"  "$CONFIG/hyprswitch/style.css"
```

- [ ] **Step 2: Add the daemon restart**

Find the "Trigger live reloads" section (around lines 47-55):

```bash
# --- Trigger live reloads ---
# Hyprland: reread config (picks up new $col_active/$col_inactive)
command -v hyprctl &>/dev/null && hyprctl reload &>/dev/null || true

# Waybar: SIGUSR2 triggers config + CSS reload
pkill -SIGUSR2 waybar 2>/dev/null || true

# Ghostty: SIGUSR2 reloads config (ghostty 1.2+)
pkill -SIGUSR2 ghostty 2>/dev/null || true
```

Add a new block after the ghostty line:

```bash
# Hyprswitch: no hot-reload for CSS; kill and relaunch the daemon.
if pgrep -x hyprswitch &>/dev/null; then
    pkill -x hyprswitch 2>/dev/null || true
    (hyprswitch init &>/dev/null & disown) || true
fi
```

- [ ] **Step 3: Verify the script parses**

Run: `bash -n ~/dotfiles/base/bin/.local/bin/theme-switch`
Expected: no output, exit code 0 (syntax OK).

- [ ] **Step 4: Run theme-switch to materialize the symlink**

First determine current theme:
Run: `cat ~/.local/state/theme-current 2>/dev/null || echo dark`
Note the value (call it `$CUR`).

Re-apply the current theme to force the new symlink to be created:
Run: `theme-switch "$CUR"`
Expected: prints `Switched to <dark|light> theme`, exit code 0.

- [ ] **Step 5: Verify the style.css symlink exists**

Run: `ls -la ~/.config/hyprswitch/style.css`
Expected: symlink pointing to either `dark.css` or `light.css`.

- [ ] **Step 6: Commit**

```bash
git add base/bin/.local/bin/theme-switch
git commit -m "theme-switch: swap and reload hyprswitch stylesheet"
```

---

## Task 6: Wire the keybinding and daemon into Hyprland

**Files:**
- Modify: `base/hypr/.config/hypr/hyprland.conf`

- [ ] **Step 1: Add the daemon exec-once**

Find the "Autostart" section in `base/hypr/.config/hypr/hyprland.conf` (around line 22-35). Add this line after `exec-once = mako` and before `exec-once = hypridle`:

```
exec-once = hyprswitch init &
```

The autostart block should now look like (context only — only the one line is new):

```
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = waybar
exec-once = mako
exec-once = hyprswitch init &
exec-once = hypridle
exec-once = $term
```

- [ ] **Step 2: Add the keybinding**

Find the "Keybindings — Window management" section (around line 104-133). After the mouse drag/resize block, add a new subsection and the bind:

```
# Window picker (digit-labeled overlay across visible windows)
bind = $mod, Tab, exec, hyprswitch gui --mod-key super_l --key tab --close default --max-switch-offset 10
```

- [ ] **Step 3: Verify the config parses**

Run: `hyprctl reload && sleep 1 && hyprctl reload`
Expected: no error output. A config error would print `config error` or similar.

- [ ] **Step 4: Start the daemon manually (first-time — won't be running yet)**

Run: `pgrep -x hyprswitch || (hyprswitch init &>/tmp/hyprswitch.log & disown)`
Expected: if daemon wasn't running, a background PID is spawned. Confirm with:

Run: `pgrep -x hyprswitch`
Expected: prints a PID.

- [ ] **Step 5: Manual verification — trigger the picker**

With at least 2 windows visible, press `Super+Tab`.
Expected:
- Overlay appears showing each visible window as a tile.
- Each tile has a small digit badge (1, 2, 3, …).
- Pressing `2` focuses the window labeled `2` and closes the overlay.
- Pressing `Esc` closes the overlay without focusing.
- Pressing `Super+Tab` again also closes the overlay.

If the overlay does not appear, check:
- Run: `cat /tmp/hyprswitch.log` — look for CSS parse errors or daemon crashes.
- Run: `pgrep -x hyprswitch` — daemon should still be running.
- Run: `hyprctl binds | grep -A2 Tab` — binding should be registered.

If CSS looks broken (no overlay, garish colors, overlapping), proceed to Task 7.

- [ ] **Step 6: Commit**

```bash
git add base/hypr/.config/hypr/hyprland.conf
git commit -m "hyprland: bind Super+Tab to hyprswitch window picker"
```

---

## Task 7: (Optional) Tune CSS by inspecting the widget tree

Only do this task if the overlay from Task 6 Step 5 looks visually broken (not merely imperfect).

**Files:**
- Modify: `base/hyprswitch/.config/hyprswitch/dark.css` and/or `light.css`

- [ ] **Step 1: Launch with GTK Inspector**

Run: `pkill hyprswitch; GTK_DEBUG=interactive hyprswitch init &`
Then trigger the picker once: press `Super+Tab`.
Expected: GTK Inspector window opens alongside the picker, showing the widget tree.

- [ ] **Step 2: Identify the real selector names**

In GTK Inspector, click the "pick widget" button (top-left), then click on elements of the picker (a tile, a digit badge, a workspace frame). The inspector's "CSS nodes" panel shows the real class names.

Compare against the selectors used in the CSS files (`.client`, `.index`, etc.). If any selector doesn't match a real widget, note the discrepancy.

- [ ] **Step 3: Adjust CSS and reload**

Edit the relevant selector(s) in `base/hyprswitch/.config/hyprswitch/dark.css` (and/or `light.css`). After each edit:

Run: `theme-switch "$(cat ~/.local/state/theme-current)"`
Then press `Super+Tab` to verify the change.

- [ ] **Step 4: Kill the GTK-Inspector-enabled daemon**

Run: `pkill hyprswitch; theme-switch "$(cat ~/.local/state/theme-current)"`
Expected: daemon restarts without the inspector.

- [ ] **Step 5: Commit if changes were made**

```bash
git add base/hyprswitch/.config/hyprswitch/*.css
git commit -m "hyprswitch: refine CSS selectors for correct styling"
```

---

## Task 8: Verify theme swap works end-to-end

**Files:** none.

- [ ] **Step 1: Record the current theme**

Run: `cat ~/.local/state/theme-current`
Note the output (call it `$ORIG`).

- [ ] **Step 2: Swap themes**

Run: `theme-switch`
Expected: prints `Switched to <other> theme`.

- [ ] **Step 3: Verify the symlink points to the new theme**

Run: `readlink ~/.config/hyprswitch/style.css`
Expected: points to the opposite of `$ORIG` (e.g., if `$ORIG=dark`, now `light.css`).

- [ ] **Step 4: Verify the daemon restarted**

Run: `pgrep -x hyprswitch`
Expected: prints a PID (daemon is running).

- [ ] **Step 5: Trigger the picker and confirm new theme applies**

Press `Super+Tab`. The overlay should use the newly-active theme's colors. Close it with `Esc`.

- [ ] **Step 6: Swap back**

Run: `theme-switch "$ORIG"`
Expected: returns to the original theme. Press `Super+Tab` again and confirm the overlay matches `$ORIG`.

(No commit — this is pure verification.)

---

## Task 9: Document in README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read the current README**

Run: `cat README.md`
Identify where other Hyprland keybindings or AUR dependencies are documented (or whether they are at all).

- [ ] **Step 2: Add the AUR install note**

If there is an existing section listing manual post-install steps or AUR packages, add:

```markdown
- `paru -S hyprswitch` — window picker triggered by Super+Tab.
```

If no such section exists, create one under a heading like `## Manual post-install`:

```markdown
## Manual post-install

- `paru -S hyprswitch` — window picker triggered by Super+Tab.
```

- [ ] **Step 3: Add the keybinding to any keybind reference**

If the README has a keybindings section, add a row:

```markdown
| `Super+Tab` | Window picker — digits label visible windows, press digit to focus |
```

If no such section exists, do not invent one — stop here.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "README: document Super+Tab window picker"
```

---

## Task 10: Final sanity pass

**Files:** none.

- [ ] **Step 1: Fresh reload of everything**

Run: `hyprctl reload`
Run: `theme-switch "$(cat ~/.local/state/theme-current)"`
Expected: no errors.

- [ ] **Step 2: Functional check with multiple windows**

Open at least 4 windows across both monitors. Press `Super+Tab`. Confirm:
- Each visible window across both monitors gets a digit.
- Digits are unique (no duplicates).
- Pressing digit `N` focuses exactly the window labeled `N`.
- The previously-focused window is indicated by `.client_active` border.

- [ ] **Step 3: Edge case — single window**

Close all but one window. Press `Super+Tab`.
Expected: overlay appears (may show just one digit), pressing `1` is a no-op or re-focuses the sole window. No crash.

- [ ] **Step 4: Edge case — cancel**

Open overlay; press `Esc`. Overlay closes, focus unchanged.
Open overlay; press `Super+Tab` again. Overlay closes, focus unchanged.

- [ ] **Step 5: Confirm no git dirty state**

Run: `git status`
Expected: clean working tree (all changes committed).

---

## Done

All commits on `main` (or the feature branch, depending on workflow). The feature is live: `Super+Tab` now opens a digit-labeled picker; theme swaps restyle it cleanly.

## Rollback

If the feature misbehaves and you want to disable it without losing work:

```bash
# Comment out the bind and exec-once in base/hypr/.config/hypr/hyprland.conf
# Then reload:
hyprctl reload
pkill hyprswitch
```

No need to uninstall the AUR package or revert stow.
