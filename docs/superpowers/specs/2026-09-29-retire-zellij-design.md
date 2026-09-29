# Retire zellij — Emacs is the workspace, remote included

**Date:** 2026-09-29
**Status:** design, decisions settled; not yet planned
**Scope:** cross-repo — `~/projects/emanix` (the zellij module, its config and
theme output) and `~/dotfiles` (host enables, the zellaude hooks, the consumer
elisp that replaces the signal, the `uplink` launcher)
**Trigger:** Scott, 2026-09-29, after `mosh whistle -- emacsclient -t` worked
from rafik: *"that is going to solve my 'remote into my workspace' problem that
zellij was an imperfect solution for."*

## Why this exists

zellij was adopted for one job: a workspace that survives a disconnect, so that
closing a laptop lid or losing a connection does not lose the session. On whistle
it arrived with the NixOS-WSL cutover (2026-07-22); on datacore on 2026-08-31, so
a remote shell would survive a reboot. zellaude — a forked zellij status-bar
plugin fed by Claude Code hooks — rode on top of it as the fleet's only answer to
"which Claude session is waiting on me".

Both jobs have moved to Emacs, and zellij is no longer doing either:

- **Nothing attaches to it.** Measured 2026-09-29: whistle's only session, `main`,
  is `EXITED` and has been for over two months; datacore's `main` is `EXITED`,
  28 days. rafik has never had zellij.
- **No Claude session runs inside it.** Every Claude session on whistle is an
  agent-shell buffer over ACP (four live that day) or an OpenRig seat in tmux.
  The zellaude hook — ten entries in the global Claude `settings.json`, reaching
  every host including rafik — fires on every event of every session and exits on
  its first line, because `$ZELLIJ_SESSION_NAME` is never set.
- **The remote-workspace job is solved better.** The Emacs daemon on whistle
  holds every buffer, agent-shell session and ghostel terminal. From rafik,
  `mosh whistle -- emacsclient -t` in a **fullscreen** ghostty is a view onto it,
  mosh carries it across a closed lid, and nothing is lost when the frame goes.

What remains is a 368-line distro module, a config tree with two WASM plugins, a
theme output nobody renders, ten dead hooks, a build script, and a Syncthing-
replicated fork — plus prose in both repos that explains the fleet in terms of a
multiplexer it no longer uses.

## What was proven before this was written

The path is not hypothetical. On 2026-09-29:

1. `rafik → ssh → whistle → emacsclient -e` returned `"3 frames on whistle"`.
2. Scott drove `mosh whistle -- emacsclient -t` in a fullscreen ghostty on rafik;
   `C-x C-f` reached whistle's Emacs.
3. With `kkp` added (dotfiles `cdd9a22`), `C-;` (dictation) and `C-c C-'`
   (claude-code-ide) both work over mosh.

**Fullscreen is load-bearing, not cosmetic.** EWM's `ewm-intercept-prefixes`
defaults to `C-x C-u C-h M-x` plus a set of `(key :fullscreen)` entries. Its
docstring: *"Plain keys are intercepted normally; :fullscreen keys are also sent
to Emacs when a fullscreen surface has focus."* So in a windowed ghostty, `C-x`
goes to rafik's Emacs; in a fullscreen one, only the `:fullscreen` entries and
`ewm-mode-map`'s own bindings (the `s-` desktop keys) are still taken, and the
Emacs keys reach whistle. `s-f` is the switch and needs no configuration.

## The shape of the change

Two phases, replacements before removal — approach 1 of three considered:

- **Phase 1 (dotfiles only):** build what replaces zellij's jobs — the `agents`
  indicator and jump command, `scott/rig-watch`, and the `uplink` launcher — and
  use them in ordinary work.
- **Gate:** Scott says go. No fixed soak period: the only judge of whether zellij
  is missed is the person who used it.
- **Phase 2 (both repos):** delete zellij from emanix and dotfiles, remove
  zellaude everywhere, rewrite the prose that assumes a multiplexer, and delete
  the zellaude fork last.

Rejected: **one cut** (fastest, but the irreversible repo deletion would land
before the replacement signal had been used once); **delete first, build later**
(zellij is idle so nothing is lost, but "later" slips and the fleet would sit
with no blocked-session signal at all).

## Decisions taken

**The replacement signal is a tab-bar count of agent-shell buffers waiting on the
human, plus a jump command** (option B of three). Rejected: nothing new (agent-
shell buffers are in Emacs, but with three to five concurrent sessions "which one
is waiting" is exactly the question zellaude answered); and a count *plus* desktop
notifications (Scott declined the notifications).

**The label is `agents`, not `claude`.** agent-shell hosts pi on rafik as well as
Claude Code on whistle; the indicator covers every agent-shell buffer.

**`blocked` is read live; only `done` is remembered.** `agent-shell-status`
already returns `busy`, `blocked` (a permission request is pending) or `ready`,
from buffer-local state. Reading it at render time means `blocked` cannot go
stale. The contrast is deliberate: OpenRig's daemon-side seat state goes stale
after an approval (its Claude hooks are SessionStart, UserPromptSubmit,
Notification and Stop; nothing fires when an approved tool starts), and
`scott/rig--segment` inherits that limit. `done` — a turn that finished while
nobody was looking — is an edge, not a state, so it has to be recorded.

**Event-driven, no timer.** agent-shell emits `turn-complete`,
`permission-request` and `input-submitted` through `agent-shell-subscribe-to`.
Subscribing per buffer costs nothing between events; a timer would scan every
buffer every few seconds to learn what the events already say.

**zellij is deleted from emanix, not merely disabled on the hosts** (option A of
two). This fleet is emanix's only consumer, and a module no host enables still has
to be read, themed and kept building.

**The zellaude fork is deleted, not archived** (option C of three). It has no push
target and upstream is ishefi's repository. Deleting it is the last step of Phase
2, after both repos are committed and pushed, because Syncthing replicates the
deletion to every host at once.

**datacore after a reboot gets a shell, not an Emacs frame** (option A of three).
datacore's Emacs daemon *is* its EWM session, started by a console login, and
datacore does not autologin — `modules/ewm.nix` defaults autologin off and only
rafik opts in, because rafik's disk is encrypted and datacore's is not. So until
someone logs in at the console, `uplink datacore` falls back to a login shell.
Rejected: enabling autologin (physical access would yield a logged-in session on
an unencrypted disk); a second headless daemon for remote use (a second Emacs on
an EWM host stops EWM and flaps the login — recorded in the fleet's history).

**The launcher is named `uplink`.** Checked free on whistle and rafik against
`jack`, `beam`, `hail` and `dial`.

**`uplink` does not fullscreen the window itself.** Toggling fullscreen from a
script flips it off when it is already on, and the script cannot cheaply know
which. It prints a one-line `s-f` reminder instead.

## Phase 1 — components

### `personal-lisp/scott-agents.el` (new)

Separate from `scott-rig.el`: it watches Emacs buffers, not a daemon, and works on
hosts with no OpenRig.

- **State.** A set of *done* buffers. A buffer enters it on `turn-complete` when
  `(get-buffer-window buf t)` is nil — not visible in any window of any frame,
  which covers a buffer shown only in rafik's tty frame. It leaves on
  `input-submitted`, when it becomes visible (`window-buffer-change-functions`),
  or when it is killed.
- **Subscription.** From `agent-shell-mode-hook` for new buffers, and once over
  `(agent-shell-buffers)` at load for buffers that already exist.
- **Segment.** `agents 1 blocked 2 done`; nil when nothing waits. `blocked`
  counts buffers whose `agent-shell-status` is `blocked`, in the `warning` face;
  `done` in the default face. Registered on `emanix/modeline-extra-segments`, as
  `scott-rig` and `scott-cpgw` are.
- **`scott/agents-next-waiting`.** Pops to the first blocked buffer, else the done
  buffer that has waited longest; showing it clears its `done`. Unbound — Scott
  picks the key, as with `scott/rig-decide`.
- **Failure discipline.** The segment must never signal: under EWM this Emacs is
  the compositor. `emanix/modeline--extra-segments` already drops a signalling
  segment; the module does not rely on that and guards its own reads.

### `scott/rig-watch` (added to `scott-rig.el`)

- Candidates from the daemon: `/api/ps`, then each rig's `/api/rigs/<id>/nodes`,
  shown as `dev-check@pearl-idm13 — needs_input`.
- Opens `*rig: <session>*` via `ghostel-exec` running `tmux attach -r -t
  <session>` — read-only, so a stray key cannot type into an agent.
- With `C-u`, attaches read-write: the way to answer a harness permission prompt,
  which is not a qitem and so is out of `scott/rig-decide`'s reach.
- Killing the buffer ends only the tmux client; the seat keeps running.

### `bin/uplink` (new, dotfiles)

`uplink [host]`, default `whistle`: `mosh <host> -- emacsclient -t`, falling back
to `exec $SHELL -l` on the far side when no Emacs server answers. Prints the `s-f`
reminder first.

## Phase 2 — removal ledger

**emanix**

| | Change |
| --- | --- |
| `home/zellij.nix` (368 lines) | delete — takes the zsh hook that lands SSH logins in `main` with it |
| `zellij/` — `config.kdl`, `layouts/`, `plugins/` incl. `zellaude.wasm`, `zellij_forgot.wasm` | delete |
| `home/default.nix` | drop the `./zellij.nix` import |
| `emacs/lisp/emanix-theme.el` + `emacs/test/emanix-theme-test.el` | remove the zellij theme output (`emanix-theme--zellij-themes-dir` and what writes to it, ~lines 188–227) and its tests |
| `emacs/config.el`, `home/ghostty.nix`, `lib/themes.nix`, `home/packages.nix`, `README.md`, `WALKTHROUGH.md` | rewrite comments that name zellij. **`M-hjkl` window motion stays**; only its "mirrors zellij" justification goes |

**dotfiles**

| | Change |
| --- | --- |
| `hosts/whistle/configuration.nix`, `hosts/datacore/configuration.nix` | drop `zellij.enable` and datacore's ten-line rationale |
| `home/scott/claude/settings.json` | remove all ten zellaude hook entries (this profile reaches rafik) |
| `bin/dot-zellaude-build` | delete |
| `bin/dot-context` | drop the `~/.config/zellij` entry |
| `modules/ssh.nix` | rewrite the mosh 7-day-timeout rationale: what survives a timed-out mosh-server is now the Emacs daemon, and a timeout costs a frame; on datacore before a console login it costs a shell, as decided above |
| `home/scott/claude.nix`, `home/scott/emacs/personal.el`, `home/scott/ssh.nix`, `bin/dot-wslg-redock`, `README.md`, `WALKTHROUGH.md` | rewrite passing references in present-tense terms |

**Live state, by hand** (not Nix-managed): `zellij delete-all-sessions` on
whistle and datacore before the package goes (the two `EXITED` records), and
`rm -r ~/.local/share/emanix/zellij-themes` where the theme generator wrote it.

**Claude memory:** update `reference_zellij_plugins`,
`reference_zellaude_no_push_target`, and the zellij lines in
`reference_mosh_reconnect_protocol`, so no later session reaches for zellij.

**Last, and separately:** delete `~/projects/work/zellaude`.

**Not touched:** `M-hjkl`, `C-c t` (ghostel), mosh, and the tmux OpenRig
installed (it lives in the imperative profile, not in either repo).

## Tests

- **`agents-elisp`** — a new flake check in dotfiles, the same shape as
  `rig-elisp`, against the pinned agent-shell so that a renamed
  `agent-shell-status` or event fails the build rather than the tab-bar. Cases:
  `turn-complete` on a hidden buffer marks done, on a visible one does not;
  visible only in another frame counts as visible; `input-submitted`, becoming
  visible, and `kill-buffer` each clear; blocked is read live and never stored;
  the segment is nil when clear; next-waiting prefers blocked over done, then the
  longest-waiting done.
- **`rig-elisp`** — extended for `scott/rig-watch`: candidates from stubbed
  `/api/ps` and nodes; read-only argv by default, read-write under `C-u`;
  `ghostel-exec` stubbed.
- **emanix** — `emanix-theme-test.el` loses its zellij cases and must still pass;
  the flake checks must build with `home/zellij.nix` gone.

## Acceptance

**Phase 1**

- `agents-elisp` and the extended `rig-elisp` pass.
- Live on whistle: a permission prompt in one agent-shell session shows
  `agents 1 blocked`, answering clears it; a turn finishing in a hidden buffer
  shows `agents 1 done`, showing the buffer clears it; `scott/agents-next-waiting`
  goes to the blocked buffer first.
- `scott/rig-watch` opens a read-only view of a live seat, keystrokes there send
  nothing, `C-u` attaches read-write, and killing the buffer leaves the seat
  running in `rig ps`.
- From rafik: `uplink` opens whistle's Emacs; `uplink datacore` opens datacore's,
  or a shell when EWM is not running there.

**Phase 2**

- `git grep -i -E 'zellij|zellaude'` is empty in both repos outside history and
  dated plan/spec files.
- Both repos build; whistle and datacore rebuild; `dot-doctor` is green on
  whistle, datacore and rafik.
- `command -v zellij` finds nothing on any host.
- A fresh Claude session starts with no hook errors on whistle **and on rafik** —
  the global `settings.json` is a store symlink, so rafik sheds the ten hooks
  only when it rebuilds.
- `uplink` still works.
- Only then: the zellaude repository is deleted.

This design claims none of that yet.

## Rollout

Phase 1 is dotfiles-only: build, `rebuild`, verify, commit, push.

Phase 2 follows the cross-repo sequencing established by the cpgw and theme work:

1. emanix: deletions, theme change, tests, checks — verified locally from
   dotfiles with `--override-input emanix path:/home/scott/projects/emanix`
2. commit emanix, and push it through rafik (whistle's GitHub identity has no
   emanix access)
3. dotfiles: `nix flake lock --update-input emanix`, then the dotfiles side of
   the ledger
4. rebuild whistle and datacore; rafik rebuilds on its next pull
5. live-state cleanup, memory updates
6. delete the zellaude fork

Steps 1 and 3 must not be split across a rebuild: dotfiles enabling
`emanix.zellij` against an emanix that no longer defines it fails evaluation.

## Risks

| Risk | Mitigation |
| --- | --- |
| agent-shell renames `agent-shell-status` or an event in an update | the flake check runs against the pinned package; a rename fails the build |
| `done` misfires for a buffer shown only in another frame (rafik's tty frame) | visibility is `get-buffer-window buf t`, which spans all frames; tested |
| the emanix push relay puts a hop between commit and fleet | dotfiles is never locked to an unpushed emanix commit; rollout step 2 precedes 3 |
| deleting the zellaude fork is irreversible on every host at once | it is the final step, after both repos are pushed and after Scott's go; Syncthing file versioning may retain a copy, but is not relied on |
| a mosh session idles past its 7-day timeout | only the frame closes; the daemon and every buffer remain |

## Documentation to update

- **The emanix manual** at `~/docs/org/websites/emanix/pages/docs/` — sixteen
  lines across `theming.org` (10), `keybindings.org` (4), `glossary.org` (1) and
  `options.org` (1). Edit only; the site is not deployed as part of this work.
- Both repos' `README.md` and `WALKTHROUGH.md` (covered by the ledger).
- The comment above `(require 'scott-rig)` in `personal.el`, which today describes
  only `rig-decide` and the rig indicator.
