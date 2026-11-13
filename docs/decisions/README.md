# Decision records

One file per decision that needs more room than a code comment can carry: a
measurement, a rejected alternative, or an incident. The code comment states
the decision and links here.

This directory is **maintained**, unlike [`../superpowers/`](../superpowers/).
If a decision changes, its record changes with it. A record describing a system
that no longer exists is a bug.

## What belongs here

- A cost that justifies a value: closure sizes, byte counts, MiB figures.
- A rejected alternative, and why it lost.
- An incident that explains a constraint.
- An exit condition: what upstream change makes a workaround droppable.

## What does not

- Anything a reader needs *while reading the code*. The decision stays in the
  comment; only the working-out moves here.
- A tutorial, a manual, or a design history. The manual is emanix.net, and
  `../superpowers/` is the history.

## Budgets

The point of this directory is that code comments stay readable. These are
guidance for authors. Only the 30-line ceiling on one comment block is enforced
(`checks/comment-budget.nix`, over every `.nix`, `.sh` and `.el` in the tree);
the shorter budgets are not, and several files exceed them.

| Where | Budget |
| --- | --- |
| File header comment | 12 lines |
| Comment on one binding or attribute | 6 lines |
| Link from code to a record | 2 lines |

Over budget means the material belongs here. It does not mean delete it. A
measurement, a rejected alternative or a verified claim is never cut — it is
relocated.

## Records

| Record | Decision |
| --- | --- |
| [`speechd.md`](speechd.md) | The distribution does not ship text-to-speech |
| [`firmware-default.md`](firmware-default.md) | Redistributable firmware is on for every host |
| [`ewm-patches.md`](ewm-patches.md) | The EWM patches: what is carried, and each one's exit condition |
| [`ewm-screenshot.md`](ewm-screenshot.md) | PrintScreen captures a region, then saves or copies it |
| [`welcome-keys-check.md`](welcome-keys-check.md) | What the welcome-key check verifies, and the reach of its extraction pattern |
| [`gpu-emacs.md`](gpu-emacs.md) | The GPU Emacs: EWM's pwayl/Skia fork, emacs-overlay as its vehicle, and three exit conditions |
| [`org-roam-db-freshness.md`](org-roam-db-freshness.md) | org-roam has no watcher: why a miss syncs, and why an idle sweep exists |
| [`agent-shell-buffer-sync.md`](agent-shell-buffer-sync.md) | The agent reads and writes Emacs buffers: the capability gap, the patch, and its fail-soft contract |
| [`symbol-coverage.md`](symbol-coverage.md) | Font symbols: the PUA half does not fall back, and the rule belongs on a frame hook |
| [`keys-never-in-the-store.md`](keys-never-in-the-store.md) | No installer image carries a key: an image is the world-readable store |
