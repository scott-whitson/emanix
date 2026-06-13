# Chapter 05 — AI Tooling

Tenet #4: **AI-augmented by default.** The pi coding agent is a first-class tool in this setup, installed by `install/07-pi.sh` and configured via `base/pi/`.

## What's installed

- **pi coding agent** — `npm install -g --prefix ~/.local @earendil-works/pi-coding-agent`, run by `install/07-pi.sh`. Requires Node/npm from apt; `01-core.sh` installs them.
- **Agent config** — `base/pi/.pi/agent/AGENTS.md`, stowed to `~/.pi/agent/AGENTS.md`
- **Extensions** — `base/pi/.pi/agent/extensions/remember.ts`, stowed to `~/.pi/agent/extensions/`

## Ownership and bootstrap

- Portable Pi assets live in `base/pi/` inside this repo.
- Datacore-specific bootstrap lives in `~/projects/datacore-config` and validates that the Pi assets were installed correctly on this host.
- The runtime target `~/.pi/agent` is generated state, not the canonical source.
- See [`../../docs/ownership-contract.md`](../../docs/ownership-contract.md) for the full split.

## Install order dependency

`install/07-pi.sh` uses system `npm` and installs pi into `~/.local`, so `~/.local/bin` must be on PATH (the shell setup already does this).

## Skills

Skills live under `~/.pi/agent/skills/` and are registered in `.atl/skill-registry.md` per project. The `base/pi/` stow package ships project-agnostic skills.

Skills packaged with the dotfiles:

- **`vaultkeeper`** — Obsidian vault maintenance: find missing connections, enrich thin notes, propose changes as diffs. Invoked with `/vaultkeeper "topic"` or `/vaultkeeper random 5`.

Skills are installed at `~/.pi/agent/skills/` and are also tracked in `base/pi/.pi/agent/skills/` so they persist across re-installs.

## Day-to-day usage patterns

- pi provides its own skill discovery — it surfaces relevant skills based on the current task context.
- The `mind` plugin from the previous agent setup has been retired; Engram handles persistent memory for project context across sessions.
- Custom extensions (like `remember.ts`) live in `~/.pi/agent/extensions/` and are stowed from `base/pi/`.

## Commit discipline

- Changes to `base/pi/` → commit in this dotfiles repo
- Skills live in both `~/.pi/agent/skills/` and `base/pi/.pi/agent/skills/` — sync changes to `base/pi/` and commit
- Engram memory is external — no `.mv2` files in the repo

## Relationship to Omarchy

Omarchy does not have this tenet. If you fork this system to a non-Scott audience, [Chapter 08 — Roll Your Own](08-roll-your-own.md) notes that the `base/pi/` package and tenet #4 are the most user-specific piece — a forker will either adopt a similar AI-augmented workflow or delete the package and settle for Omarchy-parity.
