use anyhow::Result;
use serde::Deserialize;
use std::process::Command;

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
    let arg = format!("focuswindow address:{}", address);
    let out = Command::new("hyprctl").args(["dispatch", &arg]).output()?;
    if !out.status.success() {
        anyhow::bail!("hyprctl dispatch failed: {}", String::from_utf8_lossy(&out.stderr));
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

fn main() -> Result<()> {
    let monitors = query_monitors()?;
    let clients = query_clients()?;
    eprintln!("monitors: {}, clients: {}", monitors.len(), clients.len());
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
}
