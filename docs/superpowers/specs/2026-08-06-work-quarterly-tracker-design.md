# Work Quarterly Tracker — Design

**Date:** 2026-08-06
**Status:** Approved (design), pending implementation plan

## Problem

The quarterly tracker is the "main page" that ties together what Scott is working
on in a given quarter. A personal tracker already works this way, reachable via
`C-c q` (`scott/open-quarterly-tracker` in `~/dotfiles/ioshi/i-intelligence/emacs/init.el`).

On the work laptop it does not work, for two reasons:

1. **The key resolves to the wrong tree.** `scott/open-quarterly-tracker` looks for
   `~/docs/org/YYYY-QN.org`, then `~/docs/org/Quarterly/YYYY-QN.org` — the personal
   locations at the org root. Since the March 2026 sync rework, the Syncthing folder
   root on this machine is `~/docs/org/work` (it holds the `.stfolder`), not
   `~/docs/org`. The org root contains *only* `work/`. So `C-c q` here finds nothing
   and offers to create a personal note that no peer syncs.
2. **The work quarter notes are scattered under two conventions.** Six work quarter
   notes exist, split across two locations with org-roam timestamp-prefixed filenames:
   2025-Q2 through 2026-Q1 in `work/Quarterly Notes/`, and 2026-Q2 and 2026-Q3 loose
   at the top of `work/`. This split was a mistake, not an intentional
   current-vs-archive scheme.

A secondary problem: the structure that past quarters converged on
(`Rock` / `Top of Mind` / new-items inbox / `Workspace`) decayed. 2026-Q3 has no
headings at all — a flat bullet dump. The "main page" role needs scaffolding to hold.

## Target state

```
~/docs/org/
├── Quarterly/                 (personal — not synced to the work laptop)
│   └── 2026-Q3.org            #+title: 2026-Q3
└── work/
    └── Quarterly/             single home for all work quarters
        ├── 2025-Q2.org        #+title: 2025-Q2 (Work)
        ├── 2025-Q3.org
        ├── 2025-Q4.org
        ├── 2026-Q1.org
        ├── 2026-Q2.org
        └── 2026-Q3.org
```

Filenames are clean — no org-roam `20260718100853-` prefix — so the tracker function
constructs the path directly rather than searching the roam DB for it by title. A
tracker that must *find* its file is more fragile than one that can *name* it.

Titles carry the scope: `#+title: 2026-Q3 (Work)`. Home machines see both trees, so
work and personal quarters would otherwise appear as two identically-titled nodes in
`org-roam-node-find`. The suffix disambiguates while still sorting next to its
personal counterpart.

Work uses `Quarterly/` to match the personal side's capitalization.

### New-quarter template

```org
:PROPERTIES:
:ID:       <fresh org-id>
:END:
#+title: 2026-Q4 (Work)

* Rock
* Top of Mind
* New This Quarter
* Workspace

[[id:...][2026-Q3]]
```

These sections are what past quarters already used, not an invention:

- **Rock** — the one big thing for the quarter. 2025-Q3 used a `** *Rock*` heading, and
  `work/…-rocks.org` indexes quarter → rock (one entry so far).
- **Top of Mind** — the workhorse section. `[[id:]]` links to client and initiative
  nodes as headings, each with `*Context:*` / `*P1 (now):*` / `*P2:*` /
  `*Parking lot:*` beneath. Present in every structured quarter.
- **New This Quarter** — inbox for work that appeared mid-quarter. Past quarters
  spelled it `New`, `Items from this quarter`, and `New Items from this Quarter`;
  this normalizes the name.
- **Workspace** — tooling and environment work (2025-Q3).

A `Review` section was considered and cut: no past quarter has one, so it would be
scaffolding for a habit that does not exist yet.

The trailing back-link to the prior quarter is inserted automatically, read from the
previous quarter file's `:ID:` if that file exists. Scott adds this by hand today
(2026-Q3 links back to 2026-Q2).

## The elisp change

All changes are in `~/dotfiles/ioshi/i-intelligence/emacs/init.el`, which loads on
every machine (work laptop, zord, eminix). The existing two-function pair generalizes
to be scope-aware:

- **`scott/quarterly-file (scope)`** — for `work`, returns
  `<org-directory>/work/Quarterly/YYYY-QN.org`. For `personal`, preserves current
  behavior exactly: `<org-directory>/YYYY-QN.org`, falling back to
  `<org-directory>/Quarterly/YYYY-QN.org`.
- **`scott/quarterly-scope-available-p (scope)`** — `work` is available when
  `<org-directory>/work/Quarterly/` is a directory. `personal` is available when
  `<org-directory>/Quarterly/` is a directory or *any* file matching `YYYY-QN.org`
  sits at the org root — availability asks whether the tree exists at all, not
  whether this particular quarter's note has been created yet, so the first `C-c q`
  of a new quarter still resolves to the right scope. Reading the filesystem rather
  than a hostname list means no machine-specific
  configuration to keep in sync.
- **`scott/open-quarterly-tracker`** on `C-c q` — with no prefix argument, opens
  personal if available, otherwise work. With `C-u`, always opens work.

`scott/current-quarter-name` is unchanged.

Consequences per machine: on the work laptop, personal is unavailable, so `C-c q`
opens the work tracker — a key that currently does the wrong thing starts doing the
right one. On zord and eminix, both trees are present, so `C-c q` behaves exactly as
it does today and `C-u C-c q` reaches work. No existing binding is shadowed and no
new key is introduced.

### Syncthing guard (preserved)

The current function's creation guard carries over to both scopes unchanged. A
missing quarter file prompts `yes-or-no-p` before anything is written; it never
silently creates and saves an empty template. The reason is recorded in the existing
comment: on 2026-07-16 an empty `2026-Q3` won a Syncthing conflict and quarantined
the real populated note. The work tree is the one that syncs from datacore, so the
same race applies to it.

## Migration

| from | to |
|---|---|
| `work/20260706165216-2026_q2.org` | `work/Quarterly/2026-Q2.org` |
| `work/20260718100853-2026_q3.org` | `work/Quarterly/2026-Q3.org` |
| `work/Quarterly Notes/20251222171204-2025_q3.org` | `work/Quarterly/2025-Q3.org` |
| `work/Quarterly Notes/20260104221007-2025_q2.org` | `work/Quarterly/2025-Q2.org` |
| `work/Quarterly Notes/20260426142616-2025_q4.org` | `work/Quarterly/2025-Q4.org` |
| `work/Quarterly Notes/20260426160644-2026_q1.org` | `work/Quarterly/2026-Q1.org` |

For each file: move to the new path, rewrite `#+title:` to append ` (Work)`, leave
`:ID:` and the body untouched. `work/Quarterly Notes/` is removed once empty.

Renaming is link-safe. Every inbound reference to these notes is an `[[id:]]` link
(2025-Q3 has 3 inbound files, 2026-Q2 and 2025-Q2 have 2 each, 2026-Q1 has 1), and
`id:` links resolve through the roam DB by ID, not by path. Preserving `:ID:` is
therefore the load-bearing constraint of the migration. A grep for `file:`-style
links to quarter notes found none.

Link *descriptions* keep their old text — 2026-Q3's back-link still reads `2026-Q2`,
not `2026-Q2 (Work)`. That is cosmetic and left alone.

After the moves, `org-roam-db-sync` rebuilds the DB.

### Safety

`~/docs/org/work` is a Syncthing folder with no git history, so there is no undo. A
tar snapshot to the session scratchpad is taken before any file is touched.

The migration runs on exactly one machine, with Syncthing confirmed idle before it
starts and confirmed settled before quarter notes are touched anywhere else. Peers
then see one clean set of renames rather than racing edits. Any pre-existing
sync-conflict files in the tree are checked for first.

## Verification

- Before/after `:ID:` comparison across all six files — must be byte-identical.
- All six files present under `work/Quarterly/` with `(Work)`-suffixed titles.
- `work/Quarterly Notes/` gone; no quarter files left loose in `work/`.
- `org-roam-db-sync` completes and queries six work-quarter nodes.
- `C-c q` on the work laptop opens `work/Quarterly/2026-Q3.org`.
- New-quarter template creation is exercised against a throwaway `org-directory` so
  no stray file lands in the synced tree.

## Out of scope

- Restructuring the content of past quarter notes. They keep their current freeform
  shape; only location and title change.
- The stale pre-org bash helper in `work/…-wsl_setup.org` (lines 117, 388) that
  references `<VAULT>/Quarterly Notes/$(date +%Y)-Q${quarter}.md`. Dead code
  documented in a note — noted here, not touched.
- Anything on the personal tracker side beyond the scope-aware refactor, which
  preserves its behavior exactly.
