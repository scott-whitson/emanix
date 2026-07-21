# Work Vault md → org Conversion — Design

**Date:** 2026-07-21
**Status:** Approved design, awaiting plan
**Scope:** `~/docs/org/work` on the work-WSL — 110 Obsidian-flavored `.md` notes, 19 PNGs, subdirs `Weekly Notes/` and `Infor/`, plus old-tool debris.

## Goal

The migrated work vault becomes native org-roam: every note an `.org` file with
an ID, wikilinks resolved to `id:` links, indistinguishable from the rest of
`~/docs/org`. No markdown remains; Obsidian/zk leftovers are removed.

## Decisions

| Decision | Chosen | Rejected |
| --- | --- | --- |
| Converter | pandoc (gfm→org) driven by one Python orchestrator | Pure-elisp conversion (no good md→org exporter); md-roam (keeps vault two-format forever) |
| Naming | org-roam style `YYYYMMDDHHMMSS-slug.org`, timestamp from file mtime (preserved by the migration rsync), slug from the filename | Keeping readable Obsidian names (vault stays visibly two-flavored) |
| md originals | Deleted per-file after verification | Keeping both (double hits in search/elisa/org-roam forever) |
| Debris | Delete `.zk/` and `Templates/`; keep `.canvas`/`.base` files untouched | Keeping everything; deleting the proprietary files too |
| Where it runs | The work-WSL (the vault's single writer); syncthing propagates results | Converting on datacore/eminix (violates single-writer discipline) |
| pandoc install | `nix shell nixpkgs#pandoc` for the run — one-off tool | Adding pandoc to the HM package set permanently |

## Pipeline (two passes)

**Pass 1 — map.** Walk `~/docs/org/work` for `*.md` (including subdirs). For
each: original filename stem = note TITLE; generate a UUID; compute the target
name `YYYYMMDDHHMMSS-slug.org` (mtime timestamp; slug = lowercase, spaces and
punctuation → `_`, same convention as the personal vault). Result: a
case-insensitive map `title → (uuid, target-path)`. Collisions on target name
(same mtime second + slug) get +1s bumps; collisions on title (duplicate stems
in different subdirs) are resolved to the same-directory note first, else
logged and left dangling.

**Pass 2 — convert each file.**
1. Split YAML frontmatter if present (12 files): `title:` overrides the stem
   for `#+title:` only (filename/slug still from the stem); `tags:` →
   `#+filetags: :tag1:tag2:`; all other keys dropped and logged.
2. Protect Obsidian syntax from pandoc with placeholder tokens:
   `[[Name]]`, `[[Name|alias]]`, `[[Name#Anchor]]`, `![[image.png]]`.
3. `pandoc -f gfm -t org` on the body.
4. Replace placeholders:
   - `[[Name]]` / `[[Name|alias]]` → `[[id:UUID][Name-or-alias]]` when Name
     resolves in the map (case-insensitive).
   - `[[Name#Anchor]]` → `[[id:UUID][Name]]` (anchor dropped, logged).
   - Unresolvable → `[[roam:Name]]` (org-roam dangling link — inert, greppable,
     recoverable later).
   - `![[image.png]]` → `[[file:image.png]]` (relative; images stay in place;
     spaces in filenames are fine inside `[[file:…]]`).
5. Prepend the org-roam header:
   ```
   :PROPERTIES:
   :ID:       <uuid>
   :END:
   #+title: <Title>
   ```
6. Drop the first body heading if it is a duplicate of the title
   (case-insensitive exact match), promoting nothing else.
7. Write the `.org` file (same directory as the source). The `.md` is NOT
   deleted in this step.

The script logs every action (file → file, links resolved/dangling/anchored,
frontmatter keys dropped) to `~/docs/org/work/.conversion-log.txt` for review;
the log is deleted after acceptance (it would otherwise sync forever).

## Verification, then deletion

1. **Parse gate:** every generated `.org` parses clean — `emacs --batch`
   runs org-mode's `org-element-parse-buffer` over ALL generated files and
   must return without error for each.
2. **Roam gate:** `emacs --batch` runs `org-roam-db-sync` on this machine
   (same shared init.el; org-roam-directory covers `~/docs/org` recursively),
   then queries the DB: every UUID from Pass 1 must be present as a node.
3. **Link gate:** count `id:` links in the output equals the count of resolved
   wikilinks from the log; zero raw `[[…]]` markdown-style leftovers that are
   neither `id:`, `roam:`, nor `file:` links.
4. Only after all three gates pass: delete the 110 `.md` files, `.zk/`, and
   `Templates/`. `.canvas`/`.base`/PNG/pdf/txt files stay.

**Rollback layers** (no gate ever deletes the only copy): datacore
`.stversions` (staggered, 30 days) receives every deletion; the OneDrive
snapshot `docs-retired-20260720` still holds the original vault; the
conversion log records the full mapping.

## Aftermath

- syncthing propagates `.org` + deletions to datacore (versioned) and eminix.
- On eminix, the next `org-roam-db-sync` registers ~110 new nodes; work notes
  appear in `C-c n f` by title and backlink like any personal note.
- elisa's notes index (`C-c i n`) reads org instead of md on its next parse.
- The quarterly notes (`2026-Q2`, `2026-Q3`) become org and can later merge
  into the personal quarterly-tracker workflow — out of scope here.

## Success criteria

- Zero `.md` under `~/docs/org/work`; ~110 `.org` files in roam naming, all
  registered in org-roam with IDs (verified on WSL, spot-checked on eminix).
- Formerly-wikilinked notes navigate via `id:` links; unresolved links are
  `[[roam:…]]` (count reported, not silently dropped).
- Images referenced by converted notes render (`[[file:…]]` targets exist).
- `.zk/` and `Templates/` gone; `.canvas`/`.base` untouched; `~/docs/org/work`
  synced and identical on all three nodes.

## Out of scope

Merging work quarterlies into the personal tracker; converting `.canvas`;
retro-tagging or restructuring notes; touching anything outside
`~/docs/org/work`.
