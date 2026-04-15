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
