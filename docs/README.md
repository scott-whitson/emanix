# Documentation

**The manual is at [emanix.net](https://emanix.net).**

It is not mirrored here. It used to be: `manual/` held conceptual chapters on
keybindings and theming while the website carried thinner pages on the same
subjects, and the two said different things about theming for weeks before
anyone noticed. One manual, in one place, is the whole point — so the chapters
moved to the site on 2026-08-30 and the copies here were deleted rather than
left to rot.

Source for those pages lives in the site's own tree, alongside the other two
sites it shares a design system with.

## What is still in this directory

| Path | What it is | Maintained? |
| --- | --- | --- |
| [`superpowers/specs/`](superpowers/specs/) | Design documents — what was decided and why, dated | no |
| [`superpowers/plans/`](superpowers/plans/) | Implementation plans worked from those specs | no |
| [`decisions/`](decisions/) | Why a value is what it is: measurements, rejected alternatives, exit conditions | **yes** |

`superpowers/` holds **records, not references.** They describe work at the
moment it was done and are not updated afterwards, so read them for history and
read the manual for how the system behaves now.

`checks/retired-names.nix` exempts this directory for exactly that reason: these
documents name directories that have since been renamed, and the naming is part
of the record. Everywhere else in the repository, the check fails the build.

`decisions/` is the opposite, and is kept current. Read it for why a constant,
an override strength, or a workaround is what it is. The code comment beside the
value carries the decision itself and links here for the working-out. It sits
under the same retired-name exemption, which is correct: a record of what a
value replaced may need to name the thing it replaced.

Install runbooks and per-host operational guides are in the consuming flake,
not here — they describe a specific user's hosts, keys and secrets rather than
the distribution.
