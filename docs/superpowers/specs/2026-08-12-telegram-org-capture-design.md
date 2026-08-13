# Telegram Org Capture — Design

**Date:** 2026-08-12
**Status:** Approved (design), pending implementation plan

## Problem

There is no path from the phone into the org tree. Away from a keyboard, two things
are unreachable: asking pi anything, and saving a note. The second is the frequent
one — a thought on the drive home, a photo of a whiteboard after a client session —
and today it either goes into some other app and never migrates, or it is lost.

A Telegram bot already exists on datacore, but only as uptime-kuma's *outbound*
notification channel. Nothing listens for inbound messages. What exists is a bot
token and a chat, not a receiver.

## Scope

This phase is capture only: **text and photos, from Telegram, into the current work
quarterly tracker.**

Talking to pi from the phone is deliberately out. It is the rarer need, and letting
it in now would make capture — the thing used several times a week — wait on session
lifetime, timeouts, and streaming design. The handler is structured so a later
`/ask` command is an added handler, not a rewrite.

## Prerequisite: land the work quarterly tracker

This design targets the *post-migration* tracker layout. That work is written and
green but not landed:

- Branch `worktree-work-quarterly-tracker` (worktree at
  `~/dotfiles/.claude/worktrees/work-quarterly-tracker`) holds six commits:
  `lisp/scott-quarterly.el`, its ERT suite, and `tools/migrate-work-quarters.sh`.
- `emacs -Q --batch -L lisp -L test -l test/scott-quarterly-test.el
  -f ert-run-tests-batch-and-exit` passes 14/14 as of 2026-08-12.
- Four files in that worktree are modified and uncommitted.
- Neither the merge to `main` nor the file migration has run. `work/Quarterly/`
  does not exist on any machine; the six quarter notes are still split between
  `work/Quarterly Notes/` and loose files in `work/`.

Landing it must come first, per its own spec
(`2026-08-06-work-quarterly-tracker-design.md`) and plan
(`plans/archive/2026-08-06-work-quarterly-tracker.md`). Building capture against the
current split layout would mean globbing two directories and two naming conventions,
then throwing that resolver away — and captures would land in an invented heading
rather than the `New This Quarter` section the tracker already reserves for exactly
this.

## Target state

```
~/docs/org/work/                       ← Syncthing folder root (.stfolder lives here)
├── Quarterly/
│   └── 2026-Q3.org                    ← capture target, path constructed not searched
└── assets/
    └── captures/
        └── 2026/
            └── 2026-08-12-143207.jpg  ← archived whiteboard photos

~/projects/orgcapture/                 ← laptop; Syncthing-delivered to datacore
├── pyproject.toml                       as ~/projects/work/orgcapture
├── docker-compose.yml
├── Dockerfile
├── .env                               ← uncommitted: bot token, allowed chat IDs
├── src/orgcapture/                    ← the service
└── tests/

/srv/data/stacks-state/orgcapture/     ← on datacore, bind-mounted into the container
├── journal.jsonl                      ← one record per write; powers /undo and replay dedupe
└── pending.jsonl                      ← captures parked because the quarter note is absent
```

Everything written must live under `~/docs/org/work/` — that directory, not
`~/docs/org`, holds `.stfolder`. Assets placed outside it would not sync anywhere.

## The org write path

**Target file.** Constructed, never searched:
`~/docs/org/work/Quarterly/<YYYY>-Q<N>.org`, where `N = ((month - 1) / 3) + 1` on
calendar months — the same rule as `scott-quarterly--name` in `scott-quarterly.el`.
The Python service reimplements this one-line rule rather than shelling out to
Emacs; datacore is headless and an `emacsclient` dependency there would be a new
failure mode for no gain.

**Target heading.** The first level-1 heading whose title is exactly
`New This Quarter`. This is one of the four sections in the new-quarter template
(`Rock`, `Top of Mind`, `New This Quarter`, `Workspace`) and is documented there as
the "inbox for work that appeared mid-quarter."

If the quarter note exists but has no `New This Quarter` heading — true of every
migrated pre-2026-Q4 note, including the current 2026-Q3 — the service appends the
heading at end of file, then writes beneath it. It searches by heading text, so
moving the section afterward in Emacs is safe.

Note that migrated notes keep their freeform shape, and 2026-Q3 in particular has no
level-1 headings at all: its content sits at `**` (`Beta Todos`) and `***`
(`Beta Notes`) with no parent. Appending `* New This Quarter` at end of file is still
correct there — those earlier headings simply remain as they are, above it. The
implementation must key on heading *text at level 1*, not on being the file's only
outline structure.

**Entry format.** Each capture is one level-2 subtree, so it folds and `/undo` is a
clean subtree delete:

```org
** 2026-08-12 Wed 14:32                                           :capture:
Random note text exactly as sent.
```

Timestamp is local time; the container runs `TZ=America/New_York`.

**Org-escaping is mandatory.** Message text is user data being spliced into an
outline. Any body line matching `^\*+ ` or `^#\+` is prefixed with a comma — org's
own escape (`,* `, `,#+`) — before insertion. Without this, a note that happens to
start with `* ` silently becomes a new top-level heading and restructures the
tracker. This applies to model-produced transcription text as well as to text the
user typed.

**Missing quarter note is a refusal, not a creation.** If
`Quarterly/<YYYY>-Q<N>.org` does not exist, the service must not create it. On
2026-07-16 an empty `2026-Q3` won a Syncthing conflict and quarantined the real
populated note; a headless service racing sync is strictly worse than Emacs doing it
with a `yes-or-no-p` in front. Instead the capture is appended to `pending.jsonl`
and the reply reads `parked — no 2026-Q4 note yet, hit C-c q in Emacs, then /flush`.
Pending entries are written, in order, when you send `/flush` — not implicitly on the
next successful capture. Flushing is a deliberate act because it is the one bulk write
in the system: folding it into the capture path would mean an ordinary note silently
dragging days of backlog in with it, and would blur `/undo`, which is defined as
reversing a single capture subtree. Nothing is hidden by this — the park reply names
the missing quarter and tells you the two steps.

**Atomicity.** Read the file, build the new content in memory, write to a tempfile in
the same directory, `fsync`, `os.replace`. Writes are append-only — no existing line
is ever rewritten. The worst case under a sync race is a `.sync-conflict` file that
can be diffed, not a mangled tracker.

**Undo.** Every write appends to `journal.jsonl`: `update_id`, timestamp, target
file, the exact text inserted, and a SHA-256 taken over the file's bytes from the
first byte of the inserted subtree through end of file, as they stood immediately
after the write. `/undo` re-reads the file, recomputes that hash over the same byte
range, verifies it matches, and removes the subtree. On mismatch — the file was edited in Emacs, or Syncthing delivered a change
— it refuses and says which, rather than guessing at a delete.

## The Telegram service

Python, long-polling `getUpdates` through `python-telegram-bot`. Long-polling over a
webhook on purpose: no inbound port, no Caddy route, no TLS cert to re-plumb through
the NixOS cutover.

**A dedicated bot.** A new BotFather token, separate from uptime-kuma's. Kuma only
sends, so the token could technically be shared, but two consumers on one token is a
footgun and this bot wants its own name and `/` command list.

**Authorization.** `TELEGRAM_ALLOWED_CHAT_IDS` allowlist. Messages from any other
chat are logged and ignored with no reply — an unauthorized prober should not learn
the bot is live.

**Handlers:**

| Input | Behavior |
|---|---|
| Text message | Escape, append as a capture subtree |
| Photo (± caption) | Archive, transcribe, append — see below |
| `/undo` | Revert the most recent journal entry |
| `/where` | Reply with the file path it would write to right now |
| `/flush` | Retry parked captures |
| Voice, document, video, anything else | Explicit "not handled yet" reply |

`/where` exists because the quarter boundary is the moment this is most likely to be
silently wrong, and checking should not require SSH.

Every capture replies with the exact org text written, in a code block, plus the
target file and heading. Writing happens immediately — no confirm step. Capture is
meant to be one-tap; a bad transcription is caught by reading the reply, and `/undo`
is one message away.

**Idempotency.** The update cursor is Telegram's, not ours: unconfirmed updates are
held server-side and redelivered after a restart, which is what makes messages sent
while the container is down arrive rather than vanish. Redelivery is made safe by
recording every handled `update_id` in the journal and skipping replays — so no local
offset file is needed, and none is kept.

The residual gap is narrow and accepted: an update already fetched but not yet
handled when the process dies is lost, because the library confirms the cursor on
fetch. Every successful capture replies with the org text it wrote, so a message with
no reply is the signal to resend.

**Errors never drop a message.** Any unhandled exception is caught, logged, and
replied to the sender with the error text. An error reply still commits the offset —
a message that reliably crashes the handler must not become an infinite redelivery
loop.

## Images

The largest available photo size is downloaded to
`~/docs/org/work/assets/captures/<YYYY>/<YYYY-MM-DD-HHMMSS>.jpg`. The org link is
relative to the quarter note — `[[file:../assets/captures/2026/...jpg]]` — so it
resolves on every machine regardless of home directory.

Before the vision call the image is downscaled to a 1568px long edge, which is the
useful ceiling for these models and keeps cost predictable on a phone photo.

**Transcription** goes to OpenRouter. The API key is read from
`~/.pi/agent/auth.json` (`openrouter.key`) — the same agenix-managed, Syncthing-
distributed file `scott-openrouter.el` already reads. No second copy of the key is
created. Default model `google/gemini-3-flash-preview`, overridable by env; it is
vision-capable and already in the enabled list in `~/.pi/agent/settings.json`.

The prompt instructs: transcribe the board into org body text, preserve its
structure as nested `-` lists, mark illegible regions `[?]`, do not infer or complete
content that is not visibly present, and emit body text only — no headings, since
the output is nested under a `**` subtree.

A caption, when present, is written above the transcription.

**Transcription failure still writes the entry.** On any API error, timeout, or
refusal, the subtree is written with the image link and
`(transcription failed: <reason>)`. The archived photo is never the only copy of a
capture, and a capture is never lost to a model outage.

Each photo in a multi-photo album arrives as its own update and becomes its own
capture subtree. Grouping by `media_group_id` is not attempted.

## Deployment

The service lives at `~/projects/orgcapture/` on the work laptop, which Syncthing
delivers to datacore as `~/projects/work/orgcapture/` (the laptop's `~/projects`
folder root maps to datacore's `~/projects/work`). Compose builds the image from that
source in place. Deploy is `docker compose up -d --build` on datacore.

This follows `pearl-platform`, which already lives in the projects tree with its own
compose files — not `datacore-config`, which holds third-party infrastructure stacks
pinned to published images. It also keeps a fast local test loop: the org writer is
pure and gets exercised on the laptop rather than over SSH.

Mounts: `~/docs/org/work` read-write, `~/.pi/agent/auth.json` read-only,
`/srv/data/stacks-state/orgcapture` read-write. `restart: unless-stopped`,
`TZ=America/New_York` (datacore's system zone).

Runtime state lives under `/srv/data/stacks-state/`, matching the five existing
stacks. It must not live in the projects tree: the journal and pending queue are
per-host runtime state, and syncing them back to the laptop would be meaningless at
best and, on a restore, would replay or block captures.

Packaging it as a compose stack rather than a systemd unit is deliberate: datacore's
NixOS cutover is designed to carry the compose stacks over unchanged, so this
survives the rebuild. A hand-rolled Debian systemd unit would not.

Secrets live in an uncommitted `.env` (bot token, allowed chat IDs), gitignored, with
a committed `.env.example`. After the cutover they move to agenix alongside
`secrets/openrouter-auth.age`. Note that `.env` sits in a Syncthing-replicated
directory, so the bot token reaches every peer that syncs `~/projects` — acceptable
for these three machines, and another reason to move it to agenix rather than leave
it indefinitely.

## Testing

The org writer is a pure function from (file text, capture) to file text, so it is
tested with pytest against copies of the real quarter notes:

- Bytes above the insertion point are byte-identical before and after.
- Two captures produce two sibling `**` subtrees under one `New This Quarter`.
- A note whose body begins `* Rock` is escaped to `,* Rock` and creates no heading.
- A file lacking `New This Quarter` gains exactly one, at end of file.
- `/undo` restores the file byte-for-byte; `/undo` against a file modified after the
  write refuses and leaves it untouched.
- A missing quarter file parks the capture and writes nothing.

The vision client is stubbed in tests; one test asserts that a raised exception from
it still yields a written subtree carrying the image link.

Manual smoke from the phone, after deploy: send text, send a whiteboard photo, run
`/where`, run `/undo`.

## Verification

- `/where` reports `~/docs/org/work/Quarterly/2026-Q3.org`.
- A text capture appears under `New This Quarter` in Emacs on the work laptop after
  Syncthing settles, with no conflict files in the tree.
- A whiteboard photo yields a subtree containing a legible transcription and a
  working `[[file:../assets/...]]` link that opens in Emacs.
- Killing the container mid-run and restarting it neither loses nor duplicates a
  message sent while it was down.
- `pytest` green.
- The OpenRouter key exists in exactly one place, `~/.pi/agent/auth.json`, mounted
  read-only — not copied into `.env`, the image, or the compose file. The bot token
  is plaintext in `.env` by design for this phase; `.env` is gitignored in
  `datacore-config` and moves to agenix after the cutover.

## Out of scope

- **Voice messages.** `tools/stt` already exists in dotfiles, so this is cheap to add
  later, but it is not in this phase.
- **`/ask` and any conversational pi access.** The seam is left; the feature is not
  built.
- **Routing to any file other than the current work quarter.** No agent-chosen
  headings, no client-note routing. Captures land in one known place and are triaged
  in Emacs.
- **Classification of text.** With a fixed destination heading, text needs no model
  at all. The only model call in this design is whiteboard transcription.
- **Personal (non-work) quarterly notes.** The work laptop does not sync them and
  datacore is the host doing the writing.
