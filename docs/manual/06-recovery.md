# Chapter 06 — Recovery

Dead laptop → functional workstation in ~1 hour, given the backups are intact.

## Runbook

The full disaster-recovery design is at [`docs/superpowers/specs/2026-04-18-arch-dr-design.md`](../superpowers/specs/2026-04-18-arch-dr-design.md). Read the runbook at [`recovery/README.md`](../../recovery/README.md) first. This chapter is a pointer + quick reference.

## Three recovery scenarios

| Scenario | Trigger | Path |
|---|---|---|
| **B** (primary) | Wipe + reinstall same hardware | `recovery/README.md` → archinstall → partition.sh → post-install.sh → restore from backup |
| **A** (secondary) | Replacement hardware after loss/destruction | Same as B, plus re-enrolling Tailscale, re-adding SSH keys, re-cloning `agent-skills` |
| **C** (low-priority) | Offline recovery, no internet | Deferred — needs work |

## What's in backup

Backup lives on Google Drive via `dr_backup.sh` + rclone. Includes:

- `~/` minus caches/junk (see exclusion list in `tools/dr_backup.sh`)
- Selected `/etc/` files via allowlist (see `recovery/etc-allowlist.txt`)
- LUKS header (when root is encrypted)

Does NOT include:

- `/var/` caches
- Snap/flatpak app data (tolerable loss)
- Running process state

## What's in this repo (no backup needed)

- `~/dotfiles/` itself — clone from `git@github.com:scott-whitson/dotfiles.git`
- All `install/*.sh`, `bin/dot-*`, `themes/*` — in the repo
- `recovery/archinstall.json`, `recovery/partition.sh`, `recovery/post-install.sh` — in the repo

## First-time user vs recovery

| First-time install | Recovery install |
|---|---|
| Fresh `./install.sh workstation` | Same, but preceded by `recovery/partition.sh` + archinstall |
| No restore step | `dr_restore.sh` runs after stow-base to replay the backup |
| Manual SSH keygen | SSH keys come out of the backup (`.ssh/` is backed up) |
| `sudo tailscale up` prompts auth | `sudo tailscale up --auth-key=<pre-generated>` for headless |

## Testing recovery

Rehearse on a throwaway Arch VM before you need it for real. The spec's `tests/` directory has a fake-backup generator + VM setup doc. If you haven't tested in 6+ months, trust nothing.

## When this chapter is wrong

If `dr_backup.sh` / `dr_restore.sh` change, or the backup target moves off Google Drive, this chapter goes stale fast. The spec is the source of truth; this chapter summarizes. Update both if you touch DR.
