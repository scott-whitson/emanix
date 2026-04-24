# Chapter 08 — Roll Your Own

This system is private and personal. But it was written public-shaped — with the discipline of an outside reader in mind — so if you want to fork it, you can. This chapter is your map.

## Generalizable (works for anyone)

These pieces don't depend on being Scott:

- **The install structure** (`install.sh` orchestrator + `install/NN-*.sh` modules) — swap the package list to your taste
- **The stow layout** (`base/` + `profiles/`) — rename profiles to match your machines
- **The theme system** (`themes/<name>/` + `bin/dot-theme-set` + `bin/dot-theme-toggle`) — works with any palette; ship the themes you care about
- **The `bin/dot-*` helpers** (`dot-restow`, `dot-update`, `dot-doctor`) — generic operations, not personal
- **The recovery structure** (`recovery/`) — fill in your own partition layout + allowlist
- **The Hyprland/Waybar/Mako/Fuzzel/Ghostty/btop base configs** — generic Wayland desktop, re-theme freely

## Scott-specific (rip out or replace)

These have personal state:

- **`profiles/workstation/git/.gitconfig.local`** — git identity (name + email). Replace.
- **`profiles/workstation/profile.conf`** — `OBSIDIAN_VAULT` path, possibly other env. Replace.
- **`profiles/workstation/zsh/.zshrc.d/workstation.zsh`** — any personal aliases, functions, tool integrations.
- **`profiles/workstation/zsh/.zshrc.d/claude.zsh`** — Claude Code aliases and agent-skills loader. Keep or drop depending on whether you use Claude.
- **`base/claude/.claude/settings.json`** — full Claude Code plugin + hook config. This is the biggest Scott-ism in the repo. Replace wholesale or delete.
- **`~/projects/agent-skills/`** — a separate git repo Scott maintains. Not in this repo. If you see references to the `sew` plugin or custom skills, they come from there.
- **`tools/` uv project entry points** — `yt_transcript`, `web_extract`, `news`. Keep, modify defaults, or delete.
- **`tools/window-picker/`** — a Rust window-picker. Useful for any Hyprland user; keep or remove.
- **`recovery/` specifics** — Scott's disk layout (nvme0n1, p8 preserved for gdrive). Replace.
- **Tailscale** — your tailnet, your IPs. Re-enroll.

## Which tenets you'd likely rewrite

[Chapter 07 — Philosophy](07-philosophy.md) lists six tenets. A forker's path through them:

| Tenet | Forker's likely response |
|---|---|
| 1. Local-first, data-owned | Probably keep — good tenet for anyone who values sovereignty |
| 2. Arch + Hyprland, no apologies | Keep if you're also Arch; rewrite to `<your-distro>` otherwise |
| 3. Terminal-centric, keyboard-driven | Keep if this is how you work |
| 4. AI-augmented by default | **Drop or rewrite.** This is the most Scott-specific. Fork it to `<your-AI-tool>` or retire. |
| 5. Reversible and recoverable | Keep — this one is load-bearing for anyone |
| 6. Modular like Framework | Keep — makes forking easier, which you're doing right now |

## Minimal fork path

If you want the cheapest possible fork that still works:

1. `git clone <this repo>` to your own.
2. Edit `profiles/workstation/profile.conf` — set `OBSIDIAN_VAULT` or unset it, edit other env vars.
3. Edit `profiles/workstation/git/.gitconfig.local` — your name + email.
4. Edit `profiles/workstation/zsh/.zshrc.d/workstation.zsh` — your aliases.
5. Delete `base/claude/` and `install/07-claude.sh`, and remove tenet #4 from `docs/manual/07-philosophy.md`. OR set up your own Claude Code config if you use it.
6. Edit `install/01-pacman.sh` to match your desired package set.
7. Rewrite `README.md` — the file you're reading points at docs Scott wrote for himself. You need your own.
8. `./install.sh workstation`.

## Deeper fork path

- Rename `workstation` to whatever you call your main machine
- Add new profiles as needed (`laptop`, `desktop`, `server`, etc.)
- Add your own themes in `themes/`
- Swap out tools you don't use (`lf`, `btop`, `yt-dlp`, `mpv`)

## Attribution

Fork freely; attribution appreciated but not required. The spec + plans in `docs/superpowers/` walk through how this system was built, which may save you time if you're making similar decisions.
