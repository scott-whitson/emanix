use anyhow::Result;
use gtk4::prelude::*;
use gtk4::{glib, Application, ApplicationWindow, CssProvider, DrawingArea, EventControllerKey};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use serde::Deserialize;
use std::process::Command;
use std::cell::RefCell;
use std::rc::Rc;

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
    let addr_arg = format!("address:{}", address);
    let out = Command::new("hyprctl")
        .args(["dispatch", "focuswindow", &addr_arg])
        .output()?;
    if !out.status.success() {
        anyhow::bail!("hyprctl dispatch focuswindow failed: {}", String::from_utf8_lossy(&out.stderr));
    }
    Ok(())
}

/// Move the cursor to absolute global coords. Used to defeat Hyprland's
/// follow_mouse focus re-assertion after the overlay closes.
pub fn move_cursor(x: i32, y: i32) -> Result<()> {
    let out = Command::new("hyprctl")
        .args(["dispatch", "movecursor", &x.to_string(), &y.to_string()])
        .output()?;
    if !out.status.success() {
        anyhow::bail!("hyprctl dispatch movecursor failed: {}", String::from_utf8_lossy(&out.stderr));
    }
    Ok(())
}

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
    /// Global-coordinate center of the window (for moving the cursor when
    /// dispatching focus, since Hyprland's follow_mouse=1 reasserts focus
    /// to whatever window the cursor is over).
    pub center_global: (i32, i32),
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
                center_global: (c.at[0] + c.size[0] / 2, c.at[1] + c.size[1] / 2),
            });
        }
    }
    labeled
}

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
        _ => Palette::DARK,
    }
}

// ---------- Layer 3: overlay ----------

/// Runs the overlay event loop and returns the chosen window address (if any).
/// Actual focus dispatch happens in the caller, AFTER the layer-shell surface
/// has released its exclusive keyboard grab — otherwise Hyprland restores
/// focus to the prior window instead of our target.
pub fn run_overlay(labels: Vec<LabeledWindow>, monitors: Vec<Monitor>, palette: Palette) -> Option<LabeledWindow> {
    let app = Application::builder()
        .application_id("com.whitson.window-picker")
        .build();

    let labels = Rc::new(labels);
    let monitors = Rc::new(monitors);
    let chosen: Rc<RefCell<Option<LabeledWindow>>> = Rc::new(RefCell::new(None));

    let chosen_for_activate = chosen.clone();
    app.connect_activate(move |app| {
        // Load CSS that makes the overlay window background fully transparent,
        // so our cairo-drawn dim backdrop (alpha 0.45) is the only shading.
        let provider = CssProvider::new();
        provider.load_from_data("window { background: rgba(0,0,0,0); }");
        if let Some(display) = gtk4::gdk::Display::default() {
            gtk4::style_context_add_provider_for_display(
                &display,
                &provider,
                gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION,
            );
        }
        for mon in monitors.iter() {
            let mon_labels: Vec<LabeledWindow> = labels.iter()
                .filter(|l| l.monitor_name == mon.name)
                .cloned()
                .collect();
            if mon_labels.is_empty() { continue; }
            build_window(app, mon.clone(), mon_labels, palette, chosen_for_activate.clone());
        }
    });

    app.run();
    let result = chosen.borrow().clone();
    result
}

fn build_window(
    app: &Application,
    monitor: Monitor,
    mon_labels: Vec<LabeledWindow>,
    palette: Palette,
    chosen: Rc<RefCell<Option<LabeledWindow>>>,
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
    let palette_for_draw = palette;
    area.set_draw_func(move |_area, cr, _width, _height| {
        draw_overlay(cr, &labels_for_draw, palette_for_draw);
    });
    win.set_child(Some(&area));

    let controller = EventControllerKey::new();
    let labels_for_key = Rc::new(mon_labels);
    let win_weak = win.downgrade();
    let chosen_for_key = chosen.clone();
    controller.connect_key_pressed(move |_c, keyval, _code, _state| {
        handle_key(&labels_for_key, keyval, win_weak.clone(), &chosen_for_key);
        glib::Propagation::Stop
    });
    win.add_controller(controller);

    win.present();
}

fn draw_overlay(cr: &gtk4::cairo::Context, labels: &[LabeledWindow], palette: Palette) {
    cr.set_source_rgba(palette.backdrop.0, palette.backdrop.1, palette.backdrop.2, palette.backdrop.3);
    cr.paint().ok();

    for l in labels {
        let cx = (l.rect_local.x + l.rect_local.w / 2) as f64;
        let cy = (l.rect_local.y + l.rect_local.h / 2) as f64;

        let pill_w: f64 = 96.0;
        let pill_h: f64 = 96.0;
        let radius: f64 = 20.0;
        let px = cx - pill_w / 2.0;
        let py = cy - pill_h / 2.0;

        rounded_rect(cr, px, py, pill_w, pill_h, radius);
        cr.set_source_rgba(palette.pill.0, palette.pill.1, palette.pill.2, palette.pill.3);
        cr.fill().ok();

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
    chosen: &Rc<RefCell<Option<LabeledWindow>>>,
) {
    use gtk4::gdk::Key;
    let digit_keys: [(Key, char); 9] = [
        (Key::_1, '1'), (Key::_2, '2'), (Key::_3, '3'),
        (Key::_4, '4'), (Key::_5, '5'), (Key::_6, '6'),
        (Key::_7, '7'), (Key::_8, '8'), (Key::_9, '9'),
    ];
    if let Some((_, d)) = digit_keys.iter().find(|(k, _)| *k == keyval) {
        if let Some(target) = labels.iter().find(|l| l.digit == *d) {
            *chosen.borrow_mut() = Some(target.clone());
        }
    }
    if let Some(app) = win.upgrade().and_then(|w| w.application()) {
        app.quit();
    } else if let Some(w) = win.upgrade() {
        w.close();
    }
}

fn main() -> Result<()> {
    // Log every invocation to /tmp so we can diagnose when launched via
    // hyprctl exec (where stderr goes to /dev/null).
    let log = |msg: &str| {
        use std::io::Write;
        if let Ok(mut f) = std::fs::OpenOptions::new()
            .create(true).append(true).open("/tmp/window-picker.log")
        {
            let _ = writeln!(f, "[{}] {}", std::process::id(), msg);
        }
    };
    log("invoked");
    let monitors = query_monitors()?;
    let clients = query_clients()?;
    let labels = visible_windows(&monitors, &clients);
    log(&format!("monitors={} clients={} labels={}", monitors.len(), clients.len(), labels.len()));
    if labels.len() <= 1 {
        log("exiting: <=1 label");
        return Ok(());
    }
    let palette = load_palette();
    log("starting overlay");
    let chosen = run_overlay(labels, monitors, palette);
    log(&format!("overlay returned chosen={:?}", chosen.as_ref().map(|l| &l.address)));
    if let Some(target) = chosen {
        // Hyprland's follow_mouse=1 reasserts focus to whatever window the
        // pointer is over when the layer-shell keyboard grab releases. Move
        // the cursor to the target first so follow_mouse picks the right
        // window, then belt-and-suspenders with focuswindow.
        let (cx, cy) = target.center_global;
        let _ = move_cursor(cx, cy);
        dispatch_focus(&target.address)?;
        log("cursor moved + focus dispatched");
    }
    Ok(())
}

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
            cli("0xA", 0, 1, [1000, 500], [400, 300]),
            cli("0xB", 0, 1, [ 100, 100], [400, 300]),
            cli("0xC", 0, 1, [ 100, 500], [400, 300]),
        ];
        let result = visible_windows(&monitors, &clients);
        let addrs: Vec<&str> = result.iter().map(|l| l.address.as_str()).collect();
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
            cli("0xHidden",  0, 2, [100, 100], [400, 300]),
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

    #[test]
    fn palette_defaults_to_dark_when_state_missing() {
        let tmp = std::env::temp_dir().join(format!("wp-test-{}", std::process::id()));
        std::fs::create_dir_all(&tmp).unwrap();
        let orig = std::env::var("XDG_STATE_HOME").ok();
        std::env::set_var("XDG_STATE_HOME", &tmp);
        let p = load_palette();
        assert!((p.backdrop.3 - 0.45).abs() < 1e-9);
        match orig {
            Some(v) => std::env::set_var("XDG_STATE_HOME", v),
            None => std::env::remove_var("XDG_STATE_HOME"),
        }
        let _ = std::fs::remove_dir_all(&tmp);
    }
}
