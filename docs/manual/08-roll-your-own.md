# Chapter 08 — Roll Your Own

This system is private and personal. But it was written public-shaped — with the discipline of an outside reader in mind — so if you want to fork it, you can. This chapter is your map.

## Generalizable (works for anyone)

These pieces don't depend on being Scott:

- **The install structure** (`install.sh` orchestrator + `install/NN-*.sh` modules) — swap the package list to your taste
- **The stow layout** (`base/` packages, `--no-folding` for composable dotfiles) — all packages live in one directory, no profile complexity
- **The theme system** (`themes/<name>/` + `bin/dot-theme-set` + `bin/dot-theme-toggle`) — works with any palette; ship the themes you care about
- **The `bin/dot-*` helpers** (`dot-restow`, `dot-update`, `dot-doctor`) — generic operations, not personal
- **The Hyprland/Waybar/Mako/Fuzzel/Ghostty/btop base configs** — generic Wayland desktop, re-theme freely

## Scott-specific (rip out or replace)

These have personal state:

- **`base/git/.gitconfig.local`** — git identity (name + email). Replace.
- **`base/zsh/.zshrc.d/workstation.zsh`** — personal aliases, functions, Ollama auto-start, jrnl, work-pull/work-push. Replace.
- **`base/pi/.pi/agent/AGENTS.md`** — pi agent instructions + preferences. Replace or delete.
- **`base/pi/.pi/agent/extensions/remember.ts`** — custom remember extension. Replace or delete.
- **`base/pi/.pi/agent/skills/vaultkeeper/`** — Obsidian vault maintenance skill. Keep or delete.
- **`tools/` uv project entry points** — `yt_transcript`, `web_extract`, `news`. Keep, modify defaults, or delete.
- **`tools/window-picker/`** — a Rust window-picker. Useful for any Hyprland user; keep or remove.
- **Tailscale** — your tailnet, your IPs. Re-enroll.

## Which tenets you'd likely rewrite

[Chapter 07 — Philosophy](07-philosophy.md) lists six tenets. A forker's path through them:

| Tenet | Forker's likely response |
|---|---|
| 1. Local-first, data-owned | Probably keep — good tenet for anyone who values sovereignty |
| 2. Debian + Hyprland, no apologies | Keep if you want Debian; rewrite to `<your-distro>` otherwise |
| 3. Terminal-centric, keyboard-driven | Keep if this is how you work |
| 4. AI-augmented by default | **Drop or rewrite.** This is the most Scott-specific. Fork it to `<your-AI-tool>` or retire. |
| 5. Reversible and recoverable | Keep — this one is load-bearing for anyone |
| 6. Modular like Framework | Keep — makes forking easier, which you're doing right now |

## Minimal fork path

If you want the cheapest possible fork that still works:

1. `git clone <this repo>` to your own.
2. Edit `base/git/.gitconfig.local` — your name + email.
3. Edit `base/zsh/.zshrc.d/workstation.zsh` — your aliases, remove work-pull/work-push, remove jrnl alias.
4. Delete `base/pi/` and `install/07-pi.sh`, and remove tenet #4 from `docs/manual/07-philosophy.md`. Or set up your own pi config if you use it.
5. Edit `install/01-core.sh` to match your desired package set.
6. Rewrite `README.md` — the file you're reading points at docs Scott wrote for himself. You need your own.
7. `./install.sh`.

## Deeper fork path

- Add your own themes in `themes/`
- Swap out tools you don't use (`lf`, `btop`, `yt-dlp`, `mpv`)
- Add your own stow packages to `base/` for new tools

## Attribution

Fork freely; attribution appreciated but not required. The spec + plans in `docs/superpowers/` walk through how this system was built, which may save you time if you're making similar decisions.