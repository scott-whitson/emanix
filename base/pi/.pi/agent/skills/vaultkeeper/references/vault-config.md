# Vault Configuration

## Paths

- **Vault root:** `$OBSIDIAN_VAULT` — set per-machine in `workstation.zsh`. On the work-laptop WSL this is the OneDrive `docs` vault (`/mnt/c/Users/swhitson.CENTRALDATA/OneDrive - Central Data Systems, Inc/docs`); on personal desktops it is `~/docs/vault/Whitsgrove`.
- **zk binary:** `zk` (on PATH at `~/.local/bin/zk`)
- **zk config:** `<vault-root>/.zk/config.toml`

## Conventions

- Links: wiki-style `[[Page Name]]`
- Tags: `#hashtags` (but Vaultkeeper does NOT add or propose tags)
- No frontmatter unless the note already has it
- Note filenames match their titles: `{{title}}.md`
- Editor: Helix (`hx`)

## zk Commands Reference

All commands must be run with `--notebook-dir` pointing to the vault root, or `cd` into the vault first.

```bash
VAULT="${OBSIDIAN_VAULT:?set OBSIDIAN_VAULT}"
```

| Task | Command |
|------|---------|
| List all notes | `zk list -q --notebook-dir "$VAULT"` |
| Search by content | `zk list -m "query" --notebook-dir "$VAULT"` |
| Random N notes | `zk list --sort random --limit N -q --notebook-dir "$VAULT"` |
| Backlinks to a note | `zk list --link-to "Note.md" --notebook-dir "$VAULT"` |
| Forward links from a note | `zk list --linked-by "Note.md" --notebook-dir "$VAULT"` |
| Notes mentioning a title | `zk list --mention "Note.md" --notebook-dir "$VAULT"` |
| List all tags | `zk tag list --notebook-dir "$VAULT"` |
| Note titles only | `zk list -q --format "{{title}}" --notebook-dir "$VAULT"` |
| Note paths only | `zk list -q --format "{{path}}" --notebook-dir "$VAULT"` |

## Vault Stats (as of 2026-03-02)

- ~241 notes
- ~90 notes with wikilinks, ~650 total links
- ~150 orphaned notes (no links in or out)
- Tags are sparse (mostly on tools/micro cluster)
- Flat structure with some subdirectories (Quarterly, KnowFlow, STEM, Everest, philosophy, spirituality, computing, economics, zeitgeist, me, art, media)
