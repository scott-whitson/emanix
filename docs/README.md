# Documentation

Three tiers, by what the document is *for*.

| Tier | Question it answers | Edited? |
| --- | --- | --- |
| [`manual/`](manual/) | How does this system work? | Yes — kept current |
| [`ioshi/`](ioshi/) | How do I operate *this host*? | Yes — kept current |
| [`superpowers/`](superpowers/) | Why was it built this way? | **No** — frozen records |

## manual/

Conceptual chapters, numbered 01–06. Read these to understand the system rather
than to perform a task. Superseded chapters live in
[`manual/history/`](manual/history/) so the numbered sequence describes only what
runs today.

## ioshi/

Per-host runbooks and operational guides — install procedures, cutover rituals,
sync topology. Named after the `ioshi/` module tree the system is organised
around (`i-intelligence` / `os-system` / `hi-hardware`). Finished or retired
runbooks move to [`ioshi/history/`](ioshi/history/).

## superpowers/

Dated design specs and implementation plans. **These are not edited to match
what shipped** — they record what was decided and why, at the time. Where
implementation diverged, the spec carries an "as-built correction" section
appended at the end rather than a rewritten body.

`specs/` holds designs; `plans/archive/` holds completed implementation plans.
`plans/` itself shows work in flight — currently nothing.

## Also at this level

[`new-host-checklist.md`](new-host-checklist.md) — largely superseded by
[`ioshi/eminix-install.md`](ioshi/eminix-install.md), kept for its Tailnet /
SSH / Syncthing identity steps, which are the parts the flake cannot do for you.
