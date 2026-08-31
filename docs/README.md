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

| Path | What it is |
| --- | --- |
| [`superpowers/specs/`](superpowers/specs/) | Design documents — what was decided and why, dated |
| [`superpowers/plans/`](superpowers/plans/) | Implementation plans worked from those specs |

Both are **records, not references.** They describe work at the moment it was
done and are not updated afterwards, so read them for history and read the
manual for how the system behaves now.

Install runbooks and per-host operational guides are in the consuming flake,
not here — they describe a specific user's hosts, keys and secrets rather than
the distribution.
