# Chapter 06 — Roll Your Own

This system is private and personal. But it was written public-shaped — with the discipline of an outside reader in mind — so if you want to fork it, you can. This chapter is your map.

## Generalizable (works for anyone)

These pieces don't depend on being Scott:

- **The role structure** (`profiles/eminix.nix` common core + `profiles/roles/{workstation,server,wsl}.nix` + `lib/mkHost.nix`) — swap the package list and role shapes to your taste
- **The `ioshi/` module layout** (`i-intelligence`/`os-system`/`hi-hardware`, one Home Manager or NixOS module per concern) — no stow, no profile complexity; add or remove a module per tool
- **The theme system** (`themes/<name>/` + `lib/themes.nix` generators) — works with any palette; ship the themes you care about
- **The `bin/dot-*` helpers** (`dot-context`, `dot-doctor`, `dot-repair`, `dot-bootstrap`, `dot-theme-set`, `dot-theme-toggle`) — generic operations, not personal
- **The Ghostty/btop Home Manager modules** — generic terminal config, re-theme freely (Hyprland/Mako/Fuzzel are gone — EWM replaced them, and that's a Scott-specific choice, not a generalizable one)

## Scott-specific (rip out or replace)

These have personal state:

- **`~/.gitconfig.local`** (untracked; included from `ioshi/i-intelligence/git.nix`) — git identity (name + email). Replace.
- **`ioshi/i-intelligence/zsh.nix`** — personal aliases and shell customization live directly in this module now (no separate `workstation.zsh`). Replace.
- **`ioshi/i-intelligence/pi/agent/AGENTS.md`** — pi agent instructions + preferences. Replace or delete.
- **`ioshi/i-intelligence/pi/agent/extensions/remember.ts`** — custom remember extension. Replace or delete.
- **`tools/` uv project entry points** — `yt_transcript`, `web_extract`, `news`. Keep, modify defaults, or delete.
- **Tailscale** — your tailnet, your IPs. Re-enroll.

## Which tenets you'd likely rewrite

[Chapter 05 — Philosophy](05-philosophy.md) lists seven tenets. A forker's path through them:

| Tenet | Forker's likely response |
| --- | --- |
| 1. Local-first, data-owned | Probably keep — good tenet for anyone who values sovereignty |
| 2. NixOS + EWM, no apologies | Keep if you want NixOS; rewrite to `<your-distro>` otherwise |
| 3. Terminal-centric, keyboard-driven | Keep if this is how you work |
| 4. AI-augmented by default | **Drop or rewrite.** This is the most Scott-specific. Fork it to `<your-AI-tool>` or retire. |
| 5. Reversible and recoverable | Keep — this one is load-bearing for anyone |
| 6. Modular like Framework | Keep — makes forking easier, which you're doing right now |

## Project vs lab vs installed product

A clean fork keeps three buckets separate:

- **Canonical project** — source-bearing tree you actively develop; lives on datacore as the source of truth.
- **Lab checkout** — a non-canonical editable mirror on another machine when you want to tinker without changing the canonical source.
- **Installed product** — something you run, not something you develop on that host.

## `~/lab` convention

Use `~/lab` for non-canonical checkouts you intentionally want to edit on a secondary machine.

Suggested shape:

- `~/lab/dotfiles` — a scratch or experimental mirror of the dotfiles repo
- `~/lab/<other-project>` — any other temporary or exploratory checkout that should not be treated as the authoritative source

Rules:

1. Anything under `~/lab` may be dirty and divergent.
2. Nothing in `~/lab` is the source of truth unless you explicitly promote it back to datacore.
3. Runtime-only machines should not need `~/lab` at all.
4. If a thing is only there to run, keep it out of `~/lab` and install it as a product instead.

This keeps the mental model simple: canonical projects stay canonical, lab trees stay disposable, and installed products stay installed.

For example:

- `dotfiles` and `datacore-config` are canonical projects.
- `~/lab/<name>` can host a non-canonical checkout when you want an editable copy elsewhere.
- An installed product on a runtime desktop like `rafik` — something you run rather than develop — keeps any local cache under `~/.local/share/<name>`, not `~/projects/<name>`, unless you intentionally want to debug the source there. (`fragpaper` was the standing example until it was retired on 2026-08-08.)

This distinction matters because it keeps runtime hosts simple and keeps only real development trees in project space.

## Minimal fork path

If you want the cheapest possible fork that still works:

1. `git clone <this repo>` to your own.
2. Create `~/.gitconfig.local` — your name + email (it's untracked; `ioshi/i-intelligence/git.nix` just includes it).
3. Edit `ioshi/i-intelligence/zsh.nix` — your aliases, remove anything Scott-specific.
4. Delete `ioshi/i-intelligence/pi.nix` and `ioshi/i-intelligence/pi/`, drop the import in `ioshi/i-intelligence/default.nix`, and remove tenet #4 from `docs/manual/05-philosophy.md`. Or set up your own pi config if you use it.
5. Edit `ioshi/i-intelligence/packages.nix` to match your desired package set.
6. Rewrite `README.md` — the file you're reading points at docs Scott wrote for himself. You need your own.
7. `nix build .#nixosConfigurations.<your-host>.config.system.build.toplevel`, then `sudo nixos-rebuild switch --flake .#<your-host>`.

## Deeper fork path

- Add your own themes in `themes/`
- Swap out tools you don't use (`lf`, `btop`, `yt-dlp`, `mpv`)
- Add your own Home Manager module under `ioshi/i-intelligence/` for new tools

## Attribution

Fork freely; attribution appreciated but not required.
