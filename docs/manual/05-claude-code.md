# Chapter 05 — Claude Code

Tenet #4: **AI-augmented by default.** Claude Code is a first-class tool in this setup, not a bolt-on. The `base/claude/` stow package ships configuration, plugins, and hook settings as part of the dotfiles.

## What's installed

- **Claude Code CLI** — `npm install -g @anthropic-ai/claude-code`, run by `install/07-claude.sh`. Requires Node via nvm; `06-tools.sh` places nvm on `PATH` before this script runs.
- **Settings file** — `base/claude/.claude/settings.json`, stowed to `~/.claude/settings.json`
- **Plugins** — declared in `enabledPlugins`; Claude Code fetches and installs them on first invocation. No manual `claude plugin install` step needed.
- **Custom skills (`sew` plugin)** — lives at `~/projects/agent-skills/` as a separate git repo, loaded via plugin declaration in settings

### Install order dependency

`install/07-claude.sh` re-sources `nvm.sh` before calling `npm` so it works when run standalone. If you run it before `06-tools.sh` has placed nvm on `PATH`, it will still succeed as long as `$NVM_DIR/nvm.sh` exists.

## Active plugins

All eleven plugins are declared in `settings.json` under `enabledPlugins`. Claude Code manages fetch and install automatically.

| Plugin | Source | Purpose |
|---|---|---|
| `context7@claude-plugins-official` | official | Pull current library docs on demand during sessions |
| `serena@claude-plugins-official` | official | Semantic code navigation — LSP-backed symbol search and editing |
| `superpowers@claude-plugins-official` | official | Meta-skills: brainstorming, writing plans, TDD, code review, subagent-driven dev |
| `code-review@claude-plugins-official` | official | Structured pull-request review workflow |
| `code-simplifier@claude-plugins-official` | official | Refactor suggestions focused on reducing complexity |
| `feature-dev@claude-plugins-official` | official | Guided feature development with architecture awareness |
| `frontend-design@claude-plugins-official` | official | Production-grade UI generation avoiding generic AI aesthetics |
| `playwright@claude-plugins-official` | official | Browser automation and end-to-end testing |
| `rust-analyzer-lsp@claude-plugins-official` | official | Rust LSP integration for type-aware editing |
| `claude-md-management@claude-plugins-official` | official | Audit and manage CLAUDE.md files across projects |
| `mind@memvid` | memvid | Persistent local memory via `.mv2` files |

## Global settings

`settings.json` carries two non-plugin flags:

- **`alwaysThinkingEnabled: true`** — Claude Code uses extended thinking on every response, not just when explicitly asked
- **`agentPushNotifEnabled: true`** — background agents send a desktop push notification when they finish

There are no hook entries in this settings file. Hooks, if any, live in per-project `.claude/settings.json` or `settings.local.json` files that are not committed to this repo.

## agent-skills (the `sew` plugin)

`~/projects/agent-skills/` is a separate git repo that declares the `sew` plugin. It is loaded automatically because its path is registered in `~/.claude/settings.json` (Claude Code discovers local plugins by directory convention alongside the repo).

Skills present (as of this writing):

- **`vaultkeeper`** — Obsidian vault maintenance: find missing connections, enrich thin notes, propose changes as diffs. Invoked as `/vaultkeeper "topic"` or `/vaultkeeper random 5`.

**If this directory is missing**, clone it manually — the URL is user-specific and is not hardcoded in `install/07-claude.sh`. The script prints a warning with instructions on first run:

```
WARN  ~/projects/agent-skills is not a git repo.
WARN    Clone it manually once (repo URL is user-specific):
WARN      mkdir -p ~/projects
WARN      git clone <your-agent-skills-url> ~/projects/agent-skills
```

## Authoring a new skill

Skills live in `~/projects/agent-skills/skills/<name>/`. The minimum structure:

```
~/projects/agent-skills/skills/<name>/
├── SKILL.md        # YAML frontmatter + prose instructions
├── scripts/        # optional helper scripts
└── references/     # optional reference material
```

`SKILL.md` frontmatter minimum:

```yaml
---
name: <skill-name>
description: <when this skill applies — the matcher Claude uses to decide relevance>
tools: Read, Bash, Edit   # declare only what the skill needs
---
```

Use the `superpowers:writing-skills` skill (`/writing-skills` in a Claude Code session) to scaffold and test new skills before committing them.

## Day-to-day usage patterns

A few conventions that have emerged from living with this setup:

- Start longer sessions with `/using-superpowers` to surface which skills are relevant before diving in.
- When implementing anything non-trivial: `/writing-plans` → review the plan → `/executing-plans` in a fresh session.
- Use `/vaultkeeper` from a Claude Code session in any directory — it reads the vault path from `references/vault-config.md` inside the skill.
- `mind` plugin memory persists across sessions in `~/.claude/mind.mv2`. Query it with `/mind search <term>` or `/mind recent`.

## Commit discipline

Two repos, two separate commit streams:

- Changes to `base/claude/.claude/settings.json` → commit in this dotfiles repo
- Changes to `~/projects/agent-skills/` → commit in that repo (separate push cadence)
- Memory files (`.claude/mind.mv2`) → **not committed** (add to `.gitignore` in the agent-skills repo)

Don't let settings drift: if you enable a new plugin interactively via `/config`, copy the change back into `base/claude/.claude/settings.json` and commit it so the next fresh install picks it up.

## Relationship to Omarchy

Omarchy does not have this tenet. If you fork this system to a non-Scott audience, [Chapter 08 — Roll Your Own](08-roll-your-own.md) notes that the `base/claude/` package and tenet #4 are the most user-specific piece — a forker will either adopt a similar AI-augmented workflow or delete the package and settle for Omarchy-parity.
