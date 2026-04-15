# Hyprswitch window picker — design

**Date:** 2026-04-15
**Status:** SUPERSEDED. Hyprswitch turned out to be a modal picker (centered GUI with thumbnails), not the per-window ace-jump overlay actually wanted. Replaced by the custom overlay tool design (same date, different filename). Kept for history.

## Goal

Add a keyboard-driven window picker to Hyprland: press a hotkey, see a digit label on each visible window, press that digit to focus. Reduce trackpad reliance when switching between windows that aren't a straight hjkl move away.

## User flow

1. `hyprswitch init` runs as a background daemon (via `exec-once` in hyprland config).
2. User presses **`Super+Tab`** → hyprswitch GUI appears, labeling each visible window with a digit (`1`–`9`, then `0` for the 10th).
3. User taps a digit → the matching window is focused and the GUI closes.
4. `Esc` or `Super+Tab` again → GUI closes without focusing anything.
5. Window grouping is per-monitor (hyprswitch's default behavior shows the "relevant" workspace on each monitor, which matches visible windows across both displays).

## Architecture

- **Tool:** [`hyprswitch`](https://github.com/egnrse/hyprswitch) v4+ from the Arch User Repository. Depends on `hyprland`, `gtk4`, `gtk4-layer-shell` (all already installed).
- **Daemon model:** `hyprswitch init` starts a long-lived process that owns the GTK overlay surface. `hyprswitch gui ...` sends a show-UI command to that daemon. Without the daemon, each invocation would cold-start GTK (slow) and no state could survive between key presses.
- **Close behavior:** `--close default` means the GUI opens on a hotkey press, stays visible without requiring the modifier to be held, and closes on either an index-key press (focus that window) or a repeat of the hotkey (cancel). This is the tap-tap flow, not the hold-Alt-Tab flow.
- **Label assignment:** spatial (hyprswitch default when `--sort-recent` is omitted). Digit `1` goes to the topmost/leftmost window; the same window gets the same digit each time the picker opens, provided the layout hasn't changed. Predictability matters more than recency here.
- **Label range:** `--max-switch-offset 10`. This caps at 10 visible windows. Beyond that, extra windows are unreachable via digits — the user would fall back to Super+hjkl or the trackpad. This cap is deliberate: two-digit labels would double the keystrokes and the cases where 10+ windows are visible are rare in practice.

## Component boundaries

Three discrete things, each with one job:

1. **Hyprland config** (`base/hypr/.config/hypr/hyprland.conf`) — owns the trigger keybind and daemon autostart. Knows nothing about styling.
2. **Hyprswitch CSS** (`base/hyprswitch/.config/hyprswitch/{dark,light}.css`) — owns the visual appearance of the overlay. Knows nothing about bindings or daemon lifecycle.
3. **theme-switch** (`base/bin/.local/bin/theme-switch`) — owns the dark/light swap. Knows that hyprswitch needs a daemon restart rather than a signal (hyprswitch has no CSS hot-reload).

Each can be edited independently. The CSS files are standalone artifacts; the hyprland bind is one line; theme-switch grows by two lines.

## Key bindings (hyprland.conf additions)

```hyprlang
exec-once = hyprswitch init &

bind = $mod, Tab, exec, hyprswitch gui --mod-key super_l --key tab --close default --max-switch-offset 10
```

Rationale for each flag:
- `--mod-key super_l --key tab` — identify the opener binding to hyprswitch (required flags, used internally for reverse-cycling and close-on-repeat).
- `--close default` — tap-to-open, tap-digit-to-focus. Alternative `mod-key-release` would force hold-Super, which is not the requested flow.
- `--max-switch-offset 10` — enable digit labels 1–9 + 0 for the 10th. Default is 6; we widen it because dwindle layouts often exceed 6 visible windows.

`Super+Tab` was chosen as the trigger because it is currently unbound in the user's config and follows the widely-established Tab-as-window-switcher convention. No conflict with existing workspace digits (Super+1..9) because the picker's digit capture happens inside hyprswitch's GTK surface while the overlay is open, not via Hyprland's bind system.

## Styling (dark.css, light.css)

Hyprswitch reads CSS from `~/.config/hyprswitch/style.css` at daemon startup. Following the existing waybar pattern, we ship `dark.css` and `light.css` in the repo and let `theme-switch` symlink `style.css` → the active variant. The symlink is runtime-only and not committed (matches waybar and hypr/colors/theme.conf conventions).

Color tokens must match the repo's existing Tokyo Night palette used in `base/hypr/.config/hypr/colors/dark.conf` (active border `#7aa2f7`, inactive `#414868`) and the corresponding light variant. Concrete CSS will style:
- The workspace/monitor container frames (subtle inactive border color).
- The active window frame (active border color).
- The digit label badges (contrasting background, bold monospace font).
- The overall overlay background (semi-transparent to dim the non-focused area).

Precise selectors come from inspecting hyprswitch's GTK widget tree during implementation — this will be a look-and-iterate step, not spec'd in advance.

## theme-switch integration

Two additions to `base/bin/.local/bin/theme-switch`, both in the existing "Swap symlinks" and "Trigger live reloads" sections:

```bash
# In the symlink block, alongside waybar/ghostty/hypr:
ln -sf "$target.css" "$CONFIG/hyprswitch/style.css"

# In the reload block, alongside waybar SIGUSR2 / ghostty SIGUSR2:
pkill hyprswitch 2>/dev/null && (hyprswitch init & disown) || true
```

The restart is necessary because hyprswitch loads CSS once at daemon start and does not watch the file or respond to a reload signal. A `pkill` + relaunch is fast (<200ms) and the daemon is stateless between invocations, so no user-visible impact.

## Installation

- **`install.sh`:** no code changes required. The existing `for pkg in base/*/; do stow ...` loop will stow `base/hyprswitch/` automatically. The desktop-only skip list (`hypr|waybar|mako|ghostty|fuzzel`) does not include hyprswitch — technically it should (the CSS is useless on a server profile), but the existing convention is to allow desktop-only configs to be stowed harmlessly on servers. Match that convention.
- **AUR package:** `paru -S hyprswitch` is a manual one-time step, consistent with how the user already bootstraps paru itself. Document in `README.md` under a "Post-install" section if one exists, otherwise as a top-level bullet near the install instructions.

## First-install behavior

On a fresh clone + `./install.sh personal`, the `style.css` symlink does not exist until the user runs `theme-switch` for the first time. Same pre-existing gap as waybar and hyprland colors — hyprswitch will start with its built-in default styling until `theme-switch` is invoked once. Acceptable; matches existing convention.

## Files changed

**New:**
- `base/hyprswitch/.config/hyprswitch/dark.css`
- `base/hyprswitch/.config/hyprswitch/light.css`

**Modified:**
- `base/hypr/.config/hypr/hyprland.conf` — two new lines (exec-once + bind).
- `base/bin/.local/bin/theme-switch` — two new lines (symlink + restart).
- `README.md` — one bullet documenting the manual `paru -S hyprswitch` step and the `Super+Tab` binding.

## Testing

- **Manual:** open 3+ windows across both monitors, press `Super+Tab`, verify digits appear, press each digit, confirm correct window focuses.
- **Edge: 10+ windows:** spawn 12 windows, verify first 10 get labels, remaining windows still shown but without usable digits, Super+hjkl still reaches them.
- **Edge: 1 window:** press `Super+Tab` with only one window open; should either no-op or show the single label.
- **Edge: theme swap while overlay is open:** not a real concern (user can't trigger it mid-overlay), but verify that after `theme-switch`, the next `Super+Tab` shows the new theme.
- **No unit tests** — this is pure configuration and shell; all validation is manual interactive.

## Out of scope

- Sub-second reopen animation polish.
- Custom label characters (stays digits-only per the chosen design).
- Workspace-jumping from the picker (only switches between already-visible windows).
- Scratchpad integration (special workspace excluded by default; can be added later with `--include-special-workspaces`).
- Per-monitor-only picker variant (could bind Super+Shift+Tab to `--filter-current-monitor` later if desired; not included now).

## Open implementation details

Marked explicitly so the implementer knows these need figuring out during the work, not before:

- Exact GTK CSS selectors for hyprswitch widgets — learned by inspection.
- Whether `paru` install should be added to `install.sh`'s arch desktop block or left manual — decision deferred until the implementer reads `base/paru/` and confirms the existing bootstrap story.
