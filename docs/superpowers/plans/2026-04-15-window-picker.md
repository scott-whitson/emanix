# Window Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `Super+Tab`-triggered Rust binary that overlays each visible Hyprland window with a centered digit; pressing the digit focuses the window. Cold launch under 100ms.

**Architecture:** One-shot binary (no daemon). Shell out to `hyprctl -j monitors/clients` for geometry, filter to visible windows, assign digits spatially, create one `gtk4-layer-shell` overlay per monitor, cairo-paint dim backdrop + digit pills, exit on digit keypress after `hyprctl dispatch focuswindow`.

**Tech Stack:** Rust 2021 edition, `gtk4-rs`, `gtk4-layer-shell`, `serde` + `serde_json`, `anyhow`, Hyprland IPC via `hyprctl`.

**Design spec:** `docs/superpowers/specs/2026-04-15-window-picker-design.md`

---

## File Map

**New files:**
- `tools/window-picker/Cargo.toml` — crate manifest.
- `tools/window-picker/.gitignore` — ignore `target/`.
- `tools/window-picker/src/main.rs` — all source code, three logical sections:
  1. Hyprctl layer (types + query/dispatch functions)
  2. Layout layer (`visible_windows` pure function)
  3. Overlay layer (GTK + layer-shell)
- `tools/window-picker/tests/fixtures/monitors.json` — captured real `hyprctl -j monitors` output.
- `tools/window-picker/tests/fixtures/clients.json` — captured real `hyprctl -j clients` output.
- `base/bin/.local/bin/window-picker` — shell wrapper invoking the built binary.

**Modified files:**
- `install.sh` — add one block that runs `cargo build --release` inside the crate if the binary is missing.
- `base/hypr/.config/hypr/hyprland.conf` — add one `bind = $mod, Tab, exec, window-picker` line.

**Runtime state read (not written):**
- `~/.local/state/theme-current` — either `dark` or `light`; governs palette. Managed by `theme-switch`; the binary only reads.

---

## Task 1: Scaffold the Rust crate

**Files:**
- Create: `tools/window-picker/Cargo.toml`
- Create: `tools/window-picker/.gitignore`
- Create: `tools/window-picker/src/main.rs`

- [ ] **Step 1: Verify Rust toolchain**

Run: `rustc --version && cargo --version`
Expected: both print version strings, exit 0. If absent, stop — the user's `install.sh` is supposed to have set up rustup already.

- [ ] **Step 2: Create Cargo.toml**

Create `tools/window-picker/Cargo.toml`:

```toml
[package]
name = "window-picker"
version = "0.1.0"
edition = "2021"
description = "Hyprland per-window ace-jump window picker"
license = "MIT"

[dependencies]

[profile.release]
opt-level = 3
lto = "thin"
codegen-units = 1
strip = true
```

The empty `[dependencies]` section is intentional — deps are added in later tasks to keep commits clean.

- [ ] **Step 3: Create .gitignore**

Create `tools/window-picker/.gitignore`:

```
target/
Cargo.lock
```

(The root repo `.gitignore` may or may not already cover `target/`. Include it here to be explicit, since this crate is nested.)

- [ ] **Step 4: Create empty main.rs**

Create `tools/window-picker/src/main.rs`:

```rust
fn main() {
    println!("window-picker scaffolded");
}
```

- [ ] **Step 5: Verify the crate builds**

Run: `cd tools/window-picker && cargo build --release`
Expected: build succeeds, produces `target/release/window-picker`.

Run: `./target/release/window-picker`
Expected: prints `window-picker scaffolded`.

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles
git add tools/window-picker/Cargo.toml tools/window-picker/.gitignore tools/window-picker/src/main.rs
git commit -m "window-picker: scaffold Rust crate"
```

---

## Task 2: Add non-GTK dependencies and capture fixtures

**Files:**
- Modify: `tools/window-picker/Cargo.toml` (add deps)
- Create: `tools/window-picker/tests/fixtures/monitors.json`
- Create: `tools/window-picker/tests/fixtures/clients.json`

- [ ] **Step 1: Add serde, serde_json, anyhow**

Run: `cd tools/window-picker && cargo add serde --features derive && cargo add serde_json && cargo add anyhow`
Expected: Cargo.toml's `[dependencies]` is populated with three crates at current latest-compatible versions. `cargo build` still succeeds afterwards.

- [ ] **Step 2: Capture fixture JSON from the live Hyprland session**

Run:

```bash
mkdir -p tools/window-picker/tests/fixtures
hyprctl -j monitors > tools/window-picker/tests/fixtures/monitors.json
hyprctl -j clients > tools/window-picker/tests/fixtures/clients.json
```

Expected: both files non-empty, valid JSON. Verify:

```bash
python3 -c "import json; json.load(open('tools/window-picker/tests/fixtures/monitors.json'))"
python3 -c "import json; json.load(open('tools/window-picker/tests/fixtures/clients.json'))"
```

Expected: both exit 0, no output.

- [ ] **Step 3: Verify build still clean**

Run: `cd tools/window-picker && cargo build --release`
Expected: success.

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles
git add tools/window-picker/Cargo.toml tools/window-picker/Cargo.lock tools/window-picker/tests/fixtures/
git commit -m "window-picker: add serde/anyhow deps + hyprctl fixtures"
```

---

## Task 3: Define hyprctl types (TDD)

**Files:**
- Modify: `tools/window-picker/src/main.rs` (add types + test)

Goal: `Monitor` and `Client` structs that deserialize cleanly from `hyprctl -j` output. Only capture the fields the tool actually needs.

- [ ] **Step 1: Write the failing test**

Replace `tools/window-picker/src/main.rs` with:

```rust
use anyhow::Result;
use serde::Deserialize;

// ---------- Layer 1: hyprctl types ----------

#[derive(Debug, Deserialize, Clone)]
pub struct Workspace {
    pub id: i64,
}

#[derive(Debug, Deserialize, Clone)]
pub struct Monitor {
    pub id: i64,
    pub name: String,
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    #[serde(rename = "activeWorkspace")]
    pub active_workspace: Workspace,
}

#[derive(Debug, Deserialize, Clone)]
pub struct Client {
    pub address: String,
    pub mapped: bool,
    pub hidden: bool,
    pub at: [i32; 2],
    pub size: [i32; 2],
    pub workspace: Workspace,
    pub monitor: i64,
}

fn main() -> Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const MONITORS_JSON: &str = include_str!("../tests/fixtures/monitors.json");
    const CLIENTS_JSON: &str = include_str!("../tests/fixtures/clients.json");

    #[test]
    fn monitors_fixture_parses() {
        let monitors: Vec<Monitor> = serde_json::from_str(MONITORS_JSON).unwrap();
        assert!(!monitors.is_empty(), "fixture should have at least one monitor");
        for m in &monitors {
            assert!(!m.name.is_empty());
            assert!(m.width > 0 && m.height > 0);
        }
    }

    #[test]
    fn clients_fixture_parses() {
        let clients: Vec<Client> = serde_json::from_str(CLIENTS_JSON).unwrap();
        for c in &clients {
            assert!(c.address.starts_with("0x"));
            assert!(c.size[0] >= 0 && c.size[1] >= 0);
        }
    }
}
```

- [ ] **Step 2: Run tests to confirm they pass**

Run: `cd tools/window-picker && cargo test`
Expected: both tests pass. (If the fixtures were captured from a real session with at least one window on screen, they parse.)

If a test fails with a serde error mentioning a missing or wrongly-typed field, that means the live hyprctl schema has evolved beyond what this plan assumed. In that case: inspect the fixture JSON, adjust the struct field types, re-run.

- [ ] **Step 3: Commit**

```bash
git add tools/window-picker/src/main.rs
git commit -m "window-picker: define hyprctl types and verify fixture parsing"
```

---

## Task 4: Query + dispatch functions

**Files:**
- Modify: `tools/window-picker/src/main.rs`

Goal: three tiny shell-out functions that interact with `hyprctl`. Not unit-testable (they IO); tested by wiring into `main` and running manually.

- [ ] **Step 1: Add the three functions**

In `src/main.rs`, after the `Client` struct and before `fn main()`, add:

```rust
use std::process::Command;

pub fn query_monitors() -> Result<Vec<Monitor>> {
    let out = Command::new("hyprctl").args(["-j", "monitors"]).output()?;
    if !out.status.success() {
        anyhow::bail!("hyprctl -j monitors failed: {}", String::from_utf8_lossy(&out.stderr));
    }
    Ok(serde_json::from_slice(&out.stdout)?)
}

pub fn query_clients() -> Result<Vec<Client>> {
    let out = Command::new("hyprctl").args(["-j", "clients"]).output()?;
    if !out.status.success() {
        anyhow::bail!("hyprctl -j clients failed: {}", String::from_utf8_lossy(&out.stderr));
    }
    Ok(serde_json::from_slice(&out.stdout)?)
}

pub fn dispatch_focus(address: &str) -> Result<()> {
    let arg = format!("focuswindow address:{}", address);
    let out = Command::new("hyprctl").args(["dispatch", &arg]).output()?;
    if !out.status.success() {
        anyhow::bail!("hyprctl dispatch failed: {}", String::from_utf8_lossy(&out.stderr));
    }
    Ok(())
}
```

- [ ] **Step 2: Wire main to smoke-test the queries**

Replace the existing `fn main() -> Result<()> { Ok(()) }` with:

```rust
fn main() -> Result<()> {
    let monitors = query_monitors()?;
    let clients = query_clients()?;
    eprintln!("monitors: {}, clients: {}", monitors.len(), clients.len());
    Ok(())
}
```

- [ ] **Step 3: Verify the binary runs against live Hyprland**

Run: `cd tools/window-picker && cargo run --release`
Expected: prints `monitors: N, clients: M` where N and M are plausible non-zero integers. No panics.

- [ ] **Step 4: Commit**

```bash
git add tools/window-picker/src/main.rs
git commit -m "window-picker: add hyprctl query + dispatch wrappers"
```

---

## Task 5: `visible_windows` pure function (TDD, the core logic)

**Files:**
- Modify: `tools/window-picker/src/main.rs`

Goal: given a list of monitors and clients, return up to 9 `LabeledWindow` entries in the correct spatial order, each with its rect translated to monitor-local coordinates.

This is the most important piece of logic in the tool. Heavy TDD.

- [ ] **Step 1: Add types and write the first failing test**

In `src/main.rs`, after the hyprctl functions and before `fn main()`, add:

```rust
// ---------- Layer 2: layout ----------

#[derive(Debug, Clone, PartialEq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LabeledWindow {
    pub digit: char,
    pub address: String,
    pub monitor_name: String,
    pub rect_local: Rect,
}

/// Return up to 9 labeled windows in spatial order across all visible workspaces.
///
/// A client is visible iff it is mapped, not hidden, and its workspace id matches
/// the active workspace of the monitor it is on. Monitors are ordered left-to-right
/// by their global x offset; within a monitor, windows are ordered top-to-bottom
/// then left-to-right.
pub fn visible_windows(monitors: &[Monitor], clients: &[Client]) -> Vec<LabeledWindow> {
    let mut monitors_sorted: Vec<&Monitor> = monitors.iter().collect();
    monitors_sorted.sort_by_key(|m| m.x);

    let mut labeled: Vec<LabeledWindow> = Vec::new();
    let digits: &[char] = &['1','2','3','4','5','6','7','8','9'];

    for mon in &monitors_sorted {
        let mut on_mon: Vec<&Client> = clients.iter()
            .filter(|c| c.mapped
                && !c.hidden
                && c.monitor == mon.id
                && c.workspace.id == mon.active_workspace.id)
            .collect();
        // spatial sort: rows by y, then x within row
        on_mon.sort_by(|a, b| a.at[1].cmp(&b.at[1]).then_with(|| a.at[0].cmp(&b.at[0])));
        for c in on_mon {
            if labeled.len() >= digits.len() { return labeled; }
            labeled.push(LabeledWindow {
                digit: digits[labeled.len()],
                address: c.address.clone(),
                monitor_name: mon.name.clone(),
                rect_local: Rect {
                    x: c.at[0] - mon.x,
                    y: c.at[1] - mon.y,
                    w: c.size[0],
                    h: c.size[1],
                },
            });
        }
    }
    labeled
}
```

- [ ] **Step 2: Replace the tests module with the full TDD suite**

Replace the existing `mod tests` block with:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    const MONITORS_JSON: &str = include_str!("../tests/fixtures/monitors.json");
    const CLIENTS_JSON: &str = include_str!("../tests/fixtures/clients.json");

    fn mon(id: i64, name: &str, x: i32, y: i32, w: i32, h: i32, ws: i64) -> Monitor {
        Monitor {
            id, name: name.into(), x, y, width: w, height: h,
            active_workspace: Workspace { id: ws },
        }
    }
    fn cli(addr: &str, monitor: i64, ws: i64, at: [i32;2], size: [i32;2]) -> Client {
        Client {
            address: addr.into(), mapped: true, hidden: false,
            at, size,
            workspace: Workspace { id: ws },
            monitor,
        }
    }

    #[test]
    fn fixtures_parse() {
        let _: Vec<Monitor> = serde_json::from_str(MONITORS_JSON).unwrap();
        let _: Vec<Client> = serde_json::from_str(CLIENTS_JSON).unwrap();
    }

    #[test]
    fn single_monitor_three_windows_spatial_order() {
        let monitors = vec![mon(0, "m0", 0, 0, 1920, 1080, 1)];
        let clients = vec![
            cli("0xA", 0, 1, [1000, 500], [400, 300]),  // right-middle
            cli("0xB", 0, 1, [ 100, 100], [400, 300]),  // top-left
            cli("0xC", 0, 1, [ 100, 500], [400, 300]),  // bottom-left
        ];
        let result = visible_windows(&monitors, &clients);
        let addrs: Vec<&str> = result.iter().map(|l| l.address.as_str()).collect();
        // spatial row order: top-left, then row 2: bottom-left, right-middle? No —
        // strict row-major with y-primary, x-secondary puts 0xB first, then the
        // two in the lower row ordered by x: 0xC (x=100) then 0xA (x=1000).
        assert_eq!(addrs, vec!["0xB", "0xC", "0xA"]);
        assert_eq!(result[0].digit, '1');
        assert_eq!(result[1].digit, '2');
        assert_eq!(result[2].digit, '3');
    }

    #[test]
    fn inactive_workspace_windows_excluded() {
        let monitors = vec![mon(0, "m0", 0, 0, 1920, 1080, 1)];
        let clients = vec![
            cli("0xVisible", 0, 1, [100, 100], [400, 300]),
            cli("0xHidden",  0, 2, [100, 100], [400, 300]),  // on workspace 2
        ];
        let result = visible_windows(&monitors, &clients);
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].address, "0xVisible");
    }

    #[test]
    fn unmapped_and_hidden_windows_excluded() {
        let monitors = vec![mon(0, "m0", 0, 0, 1920, 1080, 1)];
        let mut unmapped = cli("0xU", 0, 1, [100,100], [400,300]);
        unmapped.mapped = false;
        let mut hidden = cli("0xH", 0, 1, [100,100], [400,300]);
        hidden.hidden = true;
        let clients = vec![
            unmapped,
            hidden,
            cli("0xOk", 0, 1, [100,100], [400,300]),
        ];
        let result = visible_windows(&monitors, &clients);
        assert_eq!(result.iter().map(|l| l.address.as_str()).collect::<Vec<_>>(),
                   vec!["0xOk"]);
    }

    #[test]
    fn two_monitors_ordered_by_x() {
        let monitors = vec![
            mon(1, "right", 1920, 0, 1920, 1080, 7),
            mon(0, "left",     0, 0, 1920, 1080, 3),
        ];
        let clients = vec![
            cli("0xR", 1, 7, [2000, 100], [400, 300]),
            cli("0xL", 0, 3, [ 100, 100], [400, 300]),
        ];
        let result = visible_windows(&monitors, &clients);
        // left monitor first (smaller x), so 0xL gets digit 1.
        assert_eq!(result[0].address, "0xL");
        assert_eq!(result[0].digit, '1');
        assert_eq!(result[1].address, "0xR");
        assert_eq!(result[1].digit, '2');
    }

    #[test]
    fn rect_converted_to_monitor_local_coords() {
        let monitors = vec![mon(1, "right", 1920, 0, 1920, 1080, 5)];
        let clients = vec![
            cli("0xX", 1, 5, [2100, 200], [400, 300]),
        ];
        let result = visible_windows(&monitors, &clients);
        assert_eq!(result[0].rect_local, Rect { x: 180, y: 200, w: 400, h: 300 });
    }

    #[test]
    fn more_than_nine_windows_caps_at_nine() {
        let monitors = vec![mon(0, "m0", 0, 0, 1920, 1080, 1)];
        // Twelve windows stacked top to bottom so ordering is deterministic.
        let clients: Vec<Client> = (0..12)
            .map(|i| cli(&format!("0x{}", i), 0, 1, [0, i * 100], [100, 50]))
            .collect();
        let result = visible_windows(&monitors, &clients);
        assert_eq!(result.len(), 9);
        assert_eq!(result[0].digit, '1');
        assert_eq!(result[8].digit, '9');
    }

    #[test]
    fn zero_windows_returns_empty() {
        let monitors = vec![mon(0, "m0", 0, 0, 1920, 1080, 1)];
        let result = visible_windows(&monitors, &[]);
        assert!(result.is_empty());
    }
}
```

- [ ] **Step 3: Run tests**

Run: `cd tools/window-picker && cargo test`
Expected: all 8 tests pass (fixtures_parse + 7 logic tests).

If `single_monitor_three_windows_spatial_order` fails, re-check the sort comparator: `a.y.cmp(b.y).then_with(|| a.x.cmp(b.x))` — y primary, x secondary.

- [ ] **Step 4: Commit**

```bash
git add tools/window-picker/src/main.rs
git commit -m "window-picker: implement visible_windows with full TDD"
```

---

## Task 6: Palette loading

**Files:**
- Modify: `tools/window-picker/src/main.rs`

Goal: read `~/.local/state/theme-current` and return one of two hardcoded palettes.

- [ ] **Step 1: Add Palette type and loader**

In `src/main.rs`, after the layout section (after `visible_windows` and its tests still being present), add:

```rust
// ---------- Palette ----------

#[derive(Debug, Clone, Copy)]
pub struct Palette {
    /// Full-monitor dim overlay.
    pub backdrop: (f64, f64, f64, f64),
    /// Pill background.
    pub pill: (f64, f64, f64, f64),
    /// Digit text color.
    pub digit: (f64, f64, f64, f64),
}

impl Palette {
    pub const DARK: Palette = Palette {
        backdrop: (0.0, 0.0, 0.0, 0.45),
        pill:     (0.478, 0.635, 0.969, 1.0),   // #7aa2f7
        digit:    (0.102, 0.106, 0.149, 1.0),   // #1a1b26
    };
    pub const LIGHT: Palette = Palette {
        backdrop: (0.0, 0.0, 0.0, 0.30),
        pill:     (0.180, 0.490, 0.914, 1.0),   // #2e7de9
        digit:    (0.882, 0.886, 0.906, 1.0),   // #e1e2e7
    };
}

pub fn load_palette() -> Palette {
    let state = std::env::var("XDG_STATE_HOME")
        .unwrap_or_else(|_| format!("{}/.local/state", std::env::var("HOME").unwrap_or_default()));
    let path = format!("{}/theme-current", state);
    match std::fs::read_to_string(&path).ok().as_deref().map(str::trim) {
        Some("light") => Palette::LIGHT,
        _ => Palette::DARK,   // default: dark
    }
}
```

- [ ] **Step 2: Add a test for the loader**

Append inside `mod tests`:

```rust
    #[test]
    fn palette_defaults_to_dark_when_state_missing() {
        // Temporarily point XDG_STATE_HOME at a directory with no theme-current.
        let tmp = std::env::temp_dir().join(format!("wp-test-{}", std::process::id()));
        std::fs::create_dir_all(&tmp).unwrap();
        let orig = std::env::var("XDG_STATE_HOME").ok();
        std::env::set_var("XDG_STATE_HOME", &tmp);
        let p = load_palette();
        // Dark backdrop alpha is 0.45; light is 0.30.
        assert!((p.backdrop.3 - 0.45).abs() < 1e-9);
        match orig {
            Some(v) => std::env::set_var("XDG_STATE_HOME", v),
            None => std::env::remove_var("XDG_STATE_HOME"),
        }
        let _ = std::fs::remove_dir_all(&tmp);
    }
```

- [ ] **Step 3: Run tests**

Run: `cd tools/window-picker && cargo test`
Expected: all tests pass, including the new one.

- [ ] **Step 4: Commit**

```bash
git add tools/window-picker/src/main.rs
git commit -m "window-picker: load theme palette from theme-current"
```

---

## Task 7: Add GTK + layer-shell dependencies

**Files:**
- Modify: `tools/window-picker/Cargo.toml`

- [ ] **Step 1: Add the crates**

Run:

```bash
cd tools/window-picker
cargo add gtk4
cargo add gtk4-layer-shell
```

Expected: dependencies appear in Cargo.toml. `cargo build --release` takes several minutes on a fresh checkout (gtk4 has a large dependency tree) but succeeds.

- [ ] **Step 2: Verify the build**

Run: `cargo build --release`
Expected: completes successfully (first run takes 2–5 minutes; subsequent incremental builds are fast). Warnings about unused imports from the new crates are OK at this stage.

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles
git add tools/window-picker/Cargo.toml tools/window-picker/Cargo.lock
git commit -m "window-picker: add gtk4 and gtk4-layer-shell deps"
```

---

## Task 8: Implement the overlay layer

**Files:**
- Modify: `tools/window-picker/src/main.rs` (add GTK section + rewrite main)

This task is the bulk of the GTK code. Not unit-testable — manually verified at the end.

- [ ] **Step 1: Add imports and the overlay function**

In `src/main.rs`, add these imports at the top (alongside the existing ones):

```rust
use gtk4::prelude::*;
use gtk4::{glib, Application, ApplicationWindow, DrawingArea, EventControllerKey};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use std::cell::RefCell;
use std::rc::Rc;
```

After the `load_palette` function, add the overlay section:

```rust
// ---------- Layer 3: overlay ----------

pub fn run_overlay(labels: Vec<LabeledWindow>, monitors: Vec<Monitor>, palette: Palette) {
    let app = Application::builder()
        .application_id("com.whitson.window-picker")
        .build();

    let labels = Rc::new(labels);
    let monitors = Rc::new(monitors);

    app.connect_activate(move |app| {
        for mon in monitors.iter() {
            let mon_labels: Vec<LabeledWindow> = labels.iter()
                .filter(|l| l.monitor_name == mon.name)
                .cloned()
                .collect();
            if mon_labels.is_empty() { continue; }
            build_window(app, mon.clone(), mon_labels, palette);
        }
    });

    // Run with no CLI args.
    app.run_with_args::<&str>(&[]);
}

fn build_window(
    app: &Application,
    monitor: Monitor,
    mon_labels: Vec<LabeledWindow>,
    palette: Palette,
) {
    let win = ApplicationWindow::builder().application(app).build();
    win.init_layer_shell();
    win.set_layer(Layer::Overlay);
    win.set_keyboard_mode(KeyboardMode::Exclusive);
    for e in [Edge::Left, Edge::Right, Edge::Top, Edge::Bottom] {
        win.set_anchor(e, true);
    }
    // Pin the window to a specific GDK monitor by matching connector name.
    if let Some(display) = gtk4::gdk::Display::default() {
        let gdk_monitors = display.monitors();
        for i in 0..gdk_monitors.n_items() {
            if let Some(m) = gdk_monitors.item(i).and_downcast::<gtk4::gdk::Monitor>() {
                if m.connector().map(|c| c.as_str() == monitor.name).unwrap_or(false) {
                    win.set_monitor(Some(&m));
                    break;
                }
            }
        }
    }

    let area = DrawingArea::new();
    area.set_hexpand(true);
    area.set_vexpand(true);

    let labels_for_draw = mon_labels.clone();
    area.set_draw_func(move |_area, cr, _width, _height| {
        draw_overlay(cr, &labels_for_draw, palette);
    });
    win.set_child(Some(&area));

    // Key controller
    let controller = EventControllerKey::new();
    let labels_for_key = Rc::new(mon_labels);
    let win_weak = win.downgrade();
    controller.connect_key_pressed(move |_c, keyval, _code, _state| {
        handle_key(&labels_for_key, keyval, win_weak.clone());
        glib::Propagation::Stop
    });
    win.add_controller(controller);

    win.present();
}

fn draw_overlay(cr: &gtk4::cairo::Context, labels: &[LabeledWindow], palette: Palette) {
    // Dim backdrop covers the whole surface.
    cr.set_source_rgba(palette.backdrop.0, palette.backdrop.1, palette.backdrop.2, palette.backdrop.3);
    cr.paint().ok();

    for l in labels {
        let cx = (l.rect_local.x + l.rect_local.w / 2) as f64;
        let cy = (l.rect_local.y + l.rect_local.h / 2) as f64;

        // Pill sized to the digit.
        let pill_w: f64 = 96.0;
        let pill_h: f64 = 96.0;
        let radius: f64 = 20.0;
        let px = cx - pill_w / 2.0;
        let py = cy - pill_h / 2.0;

        rounded_rect(cr, px, py, pill_w, pill_h, radius);
        cr.set_source_rgba(palette.pill.0, palette.pill.1, palette.pill.2, palette.pill.3);
        cr.fill().ok();

        // Digit text centered.
        cr.set_source_rgba(palette.digit.0, palette.digit.1, palette.digit.2, palette.digit.3);
        cr.select_font_face(
            "Sans",
            gtk4::cairo::FontSlant::Normal,
            gtk4::cairo::FontWeight::Bold,
        );
        cr.set_font_size(64.0);
        let text = l.digit.to_string();
        let extents = cr.text_extents(&text).unwrap();
        let tx = cx - extents.width() / 2.0 - extents.x_bearing();
        let ty = cy - extents.height() / 2.0 - extents.y_bearing();
        cr.move_to(tx, ty);
        cr.show_text(&text).ok();
    }
}

fn rounded_rect(cr: &gtk4::cairo::Context, x: f64, y: f64, w: f64, h: f64, r: f64) {
    use std::f64::consts::PI;
    cr.new_sub_path();
    cr.arc(x + w - r, y + r, r, -PI / 2.0, 0.0);
    cr.arc(x + w - r, y + h - r, r, 0.0, PI / 2.0);
    cr.arc(x + r, y + h - r, r, PI / 2.0, PI);
    cr.arc(x + r, y + r, r, PI, 3.0 * PI / 2.0);
    cr.close_path();
}

fn handle_key(
    labels: &Rc<Vec<LabeledWindow>>,
    keyval: gtk4::gdk::Key,
    win: glib::WeakRef<ApplicationWindow>,
) {
    use gtk4::gdk::Key;
    // Digit keys
    let digit_keys: [(Key, char); 9] = [
        (Key::_1, '1'), (Key::_2, '2'), (Key::_3, '3'),
        (Key::_4, '4'), (Key::_5, '5'), (Key::_6, '6'),
        (Key::_7, '7'), (Key::_8, '8'), (Key::_9, '9'),
    ];
    if let Some((_, d)) = digit_keys.iter().find(|(k, _)| *k == keyval) {
        if let Some(target) = labels.iter().find(|l| l.digit == *d) {
            let _ = dispatch_focus(&target.address);
        }
    }
    // Any other key (including Escape) just closes.
    if let Some(app) = win.upgrade().and_then(|w| w.application()) {
        app.quit();
    } else if let Some(w) = win.upgrade() {
        w.close();
    }
}
```

- [ ] **Step 2: Rewrite main to wire everything together**

Replace the existing `fn main()` with:

```rust
fn main() -> Result<()> {
    let monitors = query_monitors()?;
    let clients = query_clients()?;
    let labels = visible_windows(&monitors, &clients);
    if labels.len() <= 1 {
        // No picker needed: zero or one visible window means either nothing to
        // choose from or the single choice is already focused.
        return Ok(());
    }
    let palette = load_palette();
    run_overlay(labels, monitors, palette);
    Ok(())
}
```

- [ ] **Step 3: Build**

Run: `cd tools/window-picker && cargo build --release`
Expected: builds cleanly. Warnings about `dead_code` on unused match arms are OK.

If the build fails with "no method named `init_layer_shell`" or similar, check that the `LayerShell` trait is in scope — the `use gtk4_layer_shell::{..., LayerShell}` import provides the extension methods.

If it fails with a version mismatch between `gtk4` and `gtk4-layer-shell` (the `-layer-shell` crate tracks a specific gtk4-rs minor version), run `cargo tree -p gtk4` and `cargo tree -p gtk4-layer-shell` to compare, then pin the gtk4 version in Cargo.toml to match what gtk4-layer-shell expects. Re-run the build.

- [ ] **Step 4: Run the tool manually**

With at least 2 visible windows open, run:

```bash
cd ~/dotfiles/tools/window-picker
./target/release/window-picker
```

Expected:
- Overlay appears on each monitor within ~100ms.
- Each visible window has a blue pill with a white digit centered on it.
- Pressing `1` focuses the window labeled 1, overlay closes.
- Pressing `Esc` closes the overlay with no focus change.
- Pressing any other key (e.g. `q`) closes the overlay.

Common failure modes and fixes:
- **Overlay covers wrong monitor:** the `set_monitor` call failed to match; print `monitor.connector()` values at startup to debug.
- **No overlay visible at all:** check that the compositor supports `wlr-layer-shell-unstable-v1` (Hyprland does) and that `keyboard_mode` is `Exclusive`. Without exclusive keyboard, the overlay might show but not capture keys.
- **Digits appear offset from window centers:** verify the `rect_local` translation matches the GDK coordinate system (should be, since layer-shell surfaces are per-monitor and their (0,0) is the monitor's top-left).

- [ ] **Step 5: Commit**

```bash
git add tools/window-picker/src/main.rs
git commit -m "window-picker: implement gtk4-layer-shell overlay and key handling"
```

---

## Task 9: Install the wrapper script

**Files:**
- Create: `base/bin/.local/bin/window-picker`

- [ ] **Step 1: Create the wrapper**

Create `base/bin/.local/bin/window-picker`:

```bash
#!/usr/bin/env bash
# Wrapper: execs the Rust window picker binary built in the dotfiles repo.
exec "$HOME/dotfiles/tools/window-picker/target/release/window-picker" "$@"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x base/bin/.local/bin/window-picker`
Expected: no output, exit 0.

- [ ] **Step 3: Re-stow so ~/.local/bin/window-picker exists**

Run: `cd ~/dotfiles && stow -d base -t "$HOME" --no-folding bin`
Expected: no conflict messages. Verify:

Run: `ls -la ~/.local/bin/window-picker`
Expected: symlink into the dotfiles repo.

Run: `window-picker --help 2>&1 | head -3 || echo 'no help flag (fine)'`
Expected: either prints a help message or falls through to launching the overlay. Either is OK — we haven't written help text, and the binary will try to talk to Hyprland.

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles
git add base/bin/.local/bin/window-picker
git commit -m "window-picker: add wrapper script in base/bin"
```

---

## Task 10: Hook the build into install.sh

**Files:**
- Modify: `install.sh`

Goal: on arch desktop profiles, ensure the window-picker binary exists at `tools/window-picker/target/release/window-picker`, building it if missing.

- [ ] **Step 1: Read the current install.sh**

Run: `cat install.sh | grep -n 'Stow base packages\|Rust\|IS_DESKTOP' | head -20`
Expected: spot the desktop-packages and Rust sections, then the "Stow base packages" loop. Insertion point: between "Rust" setup and "Stow base packages".

- [ ] **Step 2: Add the build block**

Find the line that reads exactly:

```
echo "Stowing base packages..."
```

Immediately before that line, add:

```bash
# --- Build window-picker (Hyprland overlay tool, native Rust binary) ---
if [[ "$IS_DESKTOP" == "true" && "$DISTRO" == "arch" ]]; then
    WP_BIN="$DOTFILES_DIR/tools/window-picker/target/release/window-picker"
    if [[ ! -x "$WP_BIN" ]]; then
        echo "Building window-picker..."
        (cd "$DOTFILES_DIR/tools/window-picker" && cargo build --release)
    fi
fi

```

(Note the blank line at the end so the `echo "Stowing base packages..."` line is visually separated.)

- [ ] **Step 3: Verify the script parses**

Run: `bash -n install.sh`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "install.sh: build window-picker on arch desktop profiles"
```

---

## Task 11: Bind Super+Tab in Hyprland

**Files:**
- Modify: `base/hypr/.config/hypr/hyprland.conf`

- [ ] **Step 1: Add the bind**

Open `base/hypr/.config/hypr/hyprland.conf`. Find the "Mouse drag/resize" section:

```
# Mouse drag/resize
bindm = $mod, mouse:272, movewindow
bindm = $mod, mouse:273, resizewindow
```

Immediately after `bindm = $mod, mouse:273, resizewindow`, add:

```

# Window picker (digit-labeled overlay on each visible window; press digit to focus)
bind = $mod, Tab, exec, window-picker
```

(Note the blank line before the comment, matching the file's existing section-break style.)

- [ ] **Step 2: Reload Hyprland**

Run: `hyprctl reload`
Expected: `ok` printed, no error.

- [ ] **Step 3: Live test the bind**

With at least 2 visible windows, press `Super+Tab`.
Expected: the overlay appears, digits on each window, pressing a digit focuses it.

If nothing happens, check:
- `hyprctl binds | grep -A2 Tab` should show the bind.
- `command -v window-picker` should resolve to `~/.local/bin/window-picker`.
- `window-picker` run from a terminal should produce the same overlay (isolates the bind from the binary).

- [ ] **Step 4: Commit**

```bash
git add base/hypr/.config/hypr/hyprland.conf
git commit -m "hyprland: bind Super+Tab to window-picker"
```

---

## Task 12: Final sanity pass

**Files:** none.

- [ ] **Step 1: Multi-window functional check**

Open 4+ windows spread across both monitors. Press `Super+Tab`. Confirm:
- Every visible window (across both monitors) has one digit.
- Digits are unique (1 through N, in left-to-right monitor order and top-to-bottom within each monitor).
- Pressing digit `N` focuses exactly the matching window and overlay closes.

- [ ] **Step 2: Single-window edge case**

Close all but one window. Press `Super+Tab`.
Expected: nothing happens (silent exit — already focused).

- [ ] **Step 3: Theme swap**

Run: `theme-switch`
Press `Super+Tab` again.
Expected: overlay appears in the newly-applied theme's colors (blue pill on dark dim; darker blue pill on slightly-lighter dim).

Swap back with `theme-switch`.

- [ ] **Step 4: Overflow edge case (>9 windows)**

Open 10+ windows on one workspace. Press `Super+Tab`.
Expected: only the first 9 (in spatial order) have digits. The overflow windows are on-screen but unlabeled. `Super+hjkl` still reaches them.

- [ ] **Step 5: Latency feel check**

Press `Super+Tab` several times in a row. Every invocation should feel instantaneous (no perceptible lag). If it feels slow (>150ms), time it:

```bash
time window-picker
# then press Esc quickly to dismiss
```

Expected: `real` is under 150ms including the press-Esc delay.

- [ ] **Step 6: Confirm clean git state**

Run: `git status`
Expected: clean working tree (all changes committed).

---

## Done

All commits on `main` (or whatever branch). The feature is live:
- `Super+Tab` opens the overlay.
- Digits on each visible window.
- Press digit → focus. Esc → cancel.
- Theme-aware colors.

## Rollback

If the feature misbehaves and you want to disable it:

```bash
# Comment out the bind in base/hypr/.config/hypr/hyprland.conf, then:
hyprctl reload
```

The Rust binary and wrapper can stay on disk; they're only invoked via the bind.
