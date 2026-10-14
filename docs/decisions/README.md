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

The point of this directory is that code comments stay readable.

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
| [`ewm-patches.md`](ewm-patches.md) | The two EWM patches, and when to drop them |
