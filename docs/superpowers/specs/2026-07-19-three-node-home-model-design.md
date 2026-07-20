# Three-Node Home Model — Design

**Date:** 2026-07-19
**Status:** Approved design, awaiting phase plans
**Nodes:** datacore (Debian 13 server, always-on), eminix (NixOS + EWM T14 laptop), work-WSL (Debian 13 on WSL2, corporate ThinkPad T14s)

## Goal

One coherent home across three machines: datacore and eminix share the full
personal home (docs, downloads, repos), the work laptop shares only work
content, and all three run the same home environment (Emacs, meow, elisa
tooling, CLI) from the one dotfiles flake. **Datacore is the system of
record.**

## Decisions (with alternatives considered)

| Decision | Chosen | Rejected |
| --- | --- | --- |
| Datacore OS strategy | Phased: standalone Home-Manager on Debian now; full NixOS conversion later as its own project | NixOS reinstall now (blocks everything on a risky migration); HM-forever (system of record never declarative) |
| Work-WSL strategy | Standalone Home-Manager on existing Debian WSL | NixOS-WSL (corporate/EDR risk, redo interop tuning); sync-only (config drift continues) |
| Work repos transport | Syncthing the whole `~/projects/work` tree, `.git` included | Git mirrors on datacore (safer, but user prefers zero-effort mirroring) |
| Personal repos transport | Git, as today (GitHub → datacore → eminix) | Syncthing everything (would fight the git hub in `~/projects/dotfiles`) |
| Vault placement | OneDrive Obsidian vault folds into `~/docs/org/work`; work-WSL syncs only that subtree | Separate `~/docs/work` outside the org vault; keeping personal tracker on the work side |

## The layer model

The "eminix stack" is three layers:

1. **NixOS system** — declarative OS.
2. **Home environment** — Home-Manager: Emacs (meow, elisa, org-roam), shells, CLI tools, themes.
3. **EWM session** — Emacs as Wayland compositor.

| Node | Layers | Notes |
| --- | --- | --- |
| eminix | 1 + 2 + 3 | Unchanged |
| datacore | 2 now, 1 later | `hosts/datacore/configuration.nix` + `ioshi/os-system/server.nix` stubs already exist for the eventual conversion |
| work-WSL | 2 | EWM is permanently out of scope — Windows is the compositor there |

## Stack unification (Home-Manager standalone)

- `flake.nix` gains `homeConfigurations."scott@datacore"` and
  `"scott@work"`, built from the same `home/scott/default.nix` +
  `ioshi/i-intelligence` HM layer that eminix uses.
- The HM layer becomes **portable**: GUI/EWM-coupled pieces (pointer cursor,
  Wayland tooling, anything assuming a compositor) go behind a headless/GUI
  option; Emacs config, meow, elisa deps, ghostty config, and CLI tools flow
  to every node. Existing elisp guards (`with-eval-after-load 'ewm`) already
  make init.el safe without EWM.
- Nix is installed **multi-user (daemon)** on both Debian boxes. Nothing
  system-level moves to Nix: Debian keeps sshd, docker, and syncthing on
  datacore; the WSL keeps its apt base and wsl.conf tuning.
- Elisa on non-eminix nodes: deferred. Ollama is a NixOS system service in
  the current design; datacore/WSL can adopt it later (Debian ollama or
  user-level service) — not part of this project.

## Sync topology (syncthing; datacore = hub)

| Folder id | Path | Devices | Status |
| --- | --- | --- | --- |
| `docs` | `~/docs` | datacore ↔ eminix | exists |
| `pi-agent` | `~/.pi/agent` | datacore ↔ eminix | exists |
| `downloads` | `~/downloads` (verify actual casing per machine in Phase 2) | datacore ↔ eminix | new |
| `work-docs` | `~/docs/org/work` | datacore ↔ work-WSL | new |
| `work-projects` | `~/projects/work` | datacore ↔ eminix ↔ work-WSL | new |

- `work-docs` is a **nested share**: `~/docs/org/work` sits inside the
  existing `docs` folder. Safe because the device sets differ — eminix
  receives the subtree through `docs`; work-WSL receives it through
  `work-docs`; datacore holds both. Never share overlapping trees to the
  *same* device pair.
- **Datacore enables staggered file versioning on every share.** This is
  what makes "system of record" operational: datacore is always on and keeps
  history when a sync goes wrong.
- Personal `~/projects` and `~/dotfiles` are **excluded from syncthing**
  entirely; they move over git exactly as today (GitHub → datacore
  `updateInstead` → eminix). Syncthing must never touch
  `datacore:~/projects/dotfiles` — it is the git hub.
- Work-WSL connectivity: tailscale runs **userspace** on the WSL (kernel
  can't route tailnet IPs), so syncthing starts on **global discovery +
  public relays** (encrypted end-to-end, zero network changes). If relay
  throughput annoys, upgrade to a direct connection via the tailscaled
  SOCKS5 proxy or a `tailscale serve` forward — an optimization, not a
  requirement.

## Work content

- **In scope:** work documents and the projects Scott owns.
  - OneDrive Obsidian vault contents move into `~/docs/org/work` (files
    as-is; markdown converts to org opportunistically, later, not as part
    of this project). OneDrive sync is then **retired for that content** —
    one sync engine per tree, never OneDrive and syncthing on the same
    files.
  - Work repos (cd-audit, pearl-platform, …) live inside the synced
    `~/projects/work`.
- **Out of scope:** `~/clients` data **never leaves the work laptop**. Not
  synced, not copied, not mirrored.
- **Single-writer discipline** for work repos: the work laptop is the
  writing machine; datacore and eminix treat those repos as read-mostly.
  Concurrent git operations on two nodes is the failure mode syncthing
  cannot merge — if it happens, restore from datacore's versions.

## Emacs access on the work laptop

The WSL Emacs daemon serves everything; a Windows-native Emacs client is a
dead end (frames are created by the daemon process — a Linux daemon cannot
open a Windows-native frame).

1. **Preferred:** `emacsclient -c` under **WSLg** — the daemon opens a pgtk
   frame that Windows presents as a normal window (taskbar, alt-tab,
   clipboard). Verify WSLg availability (`wsl --version`) during Phase 1.
2. **Fallback:** `emacsclient -t` (`et` alias) in Windows Terminal/ghostty.

## Phasing

One umbrella spec (this document); three plans, executed in order, each
independently shippable:

1. **Phase 1 — Stack:** make the HM layer portable, add
   `homeConfigurations`, install Nix + HM on datacore, then work-WSL;
   verify Emacs access (WSLg or terminal).
2. **Phase 2 — Personal sync:** add the `downloads` share; enable staggered
   versioning on all datacore shares.
3. **Phase 3 — Work content:** create `~/docs/org/work` and
   `~/projects/work`; migrate the OneDrive vault and retire OneDrive for
   it; stand up syncthing on the work-WSL; add `work-docs` and
   `work-projects` shares; verify relay connectivity.

## Risks and mitigations

- **Git repos inside syncthing** (`work-projects`): sync-conflict files in
  `.git` can corrupt a repo. Mitigated by single-writer discipline +
  datacore versioning. Accepted knowingly over the git-mirror alternative.
- **Credential history replicates.** Work repo histories contain real
  `.ionapi` credentials (2026-06-15 audit). Phase 3 copies that history to
  two personal machines. The pending key rotation + history rewrite should
  land **before** Phase 3.
- **EDR churn.** SentinelOne scans syncthing's file churn on the work
  laptop; watch for the known wslservice/relay CPU heat patterns during
  Phase 3.
- **Nested share** (`work-docs` inside `docs`): supported pattern with
  distinct device sets, but any future device added to *both* folders would
  create an overlap — the topology table above is the rule of record.
- **HM on foreign distros** drifts from NixOS behavior (fonts, XDG paths,
  systemd user units on WSL). Phase 1 verifies Emacs + shells on both
  targets before calling the stack "shared."

## Success criteria

- `home-manager switch --flake ~/dotfiles#scott@datacore` (and `#scott@work`)
  produce the same Emacs/meow/CLI home as eminix, minus GUI/EWM pieces.
- Editing a file in `~/docs/org/work` on the work laptop shows up on
  datacore and eminix (via `docs`); a personal note in `~/docs/org` never
  appears on the work laptop.
- Datacore holds versioned history for every share.
- OneDrive no longer syncs the migrated vault; `~/clients` remains only on
  the work laptop.
