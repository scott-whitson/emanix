# org-roam has no watcher: the db is refreshed by a miss, and by an idle sweep

**Applies to** the `org-roam` block in `emacs/config.el`. **Decided**
2026-09-28, after six files went missing from `org-roam.db`. **Relocated** here
on 2026-11-02, when the rationale moved out of the comment to fit the 30-line
budget.

## Decision

Two triggers keep the db fresh: a lookup that misses syncs once and retries, and
a 30-minute idle sweep catches changes no lookup reaches. A cheap mtime
pre-check is rejected.

## Why a trigger is needed at all

`org-roam-db-autosync-mode` (org-roam-db.el, 20260425.1623) indexes through
exactly four paths: a `find-file-hook` that indexes the file you visit, an
`after-save-hook` on buffers that already visited one, advice on
`rename-file`/`delete-file`, and ONE full `org-roam-db-sync` at mode enable —
that is, at daemon start. There is no watcher anywhere in the package: grep
`add-watch`/`file-notify` across the installed org-roam and you get zero hits.

A `.org` file created by anything that is not Emacs — Syncthing, a script, an
agent writing into `~/docs/org` — therefore stays invisible to the db until
something visits it, and the daemon runs for weeks, so the gap only widens.

## The symptom is a frozen Emacs, not a missing node

org-roam-id.el puts `org-roam-id-find` on `org-id-find` as `:before-until`
advice, so a miss falls through to plain org-id, which finds no
`org-id-locations` file on this host and walks the vault hunting the uuid. Every
`[[id:...]]` link to an unindexed file hung behind a spinning cursor.

## The measurement

2026-09-28: six externally-created files were missing from `org-roam.db` —
`spirituality/Pocket Buddhism.org`, `spirituality/Pocket Zen.org`,
`Zurvan Akarana.org`, and three under `websites/emanix/pages/docs/` — and one
stale row had survived an external rename.

## The two triggers, and why two

They cover failure modes with different latencies.

1. **A lookup that misses** syncs once and retries. `org-id-find` is the only
   place the staleness becomes visible to a user, and this is what makes a dead
   link repair itself. Cooldown-gated (`emanix/org-roam-miss-cooldown`, 60 s) so
   a genuinely bogus id cannot buy a full vault sync on every click. The
   timestamp is stamped BEFORE the sync so a nested lookup inside
   `org-roam-db-sync` sees the cooldown and cannot recurse.
2. **An idle sweep** catches what no lookup reaches: external edits to
   already-indexed files (stale titles and headlines), and external deletes
   (ghost nodes `org-roam-node-find` keeps offering). Idle rather than
   wall-clock so it never competes with typing, and 30 minutes because the sweep
   re-hashes every file in the tree to find changes.

Re-evaluating the buffer must not stack a second timer, hence the cancel-then-set
on `emanix/org-roam-idle-sync-timer` and `emanix/org-roam-deferred-sync-timer`.

## The rejected alternative

A cheap mtime pre-check was considered and rejected: a wrong comparison fails by
NEVER syncing, which is the exact bug this section exists to fix. The sweep is
affordable because it runs at idle and only files whose hash moved are
re-parsed.
