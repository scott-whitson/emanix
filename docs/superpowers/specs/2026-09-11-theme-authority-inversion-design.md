# Theme authority inversion — Emacs owns the switch

**Date:** 2026-09-11
**Status:** design, decisions settled; not yet planned
**Scope:** cross-repo — `~/projects/emanix` (mechanism) and `~/dotfiles` (the
consumer's registrations and the two wrapper scripts)
**Trigger:** a cohesion audit of both repos, asking what non-Emacs technology
is doing a job Emacs should own in the `i` (intelligence interface) concern.

## Why this exists

`bin/dot-theme-set` is 228 lines of bash that owns the runtime theme. It writes
the state markers, symlinks per-app theme files for three programs, JSON-patches
two agent configs through embedded Python heredocs, calls `gsettings`, signals
ghostty — and, as its **last** step, hands the theme name to Emacs:

```sh
"$EMACSCLIENT" -e "(emanix/theme-set \"$THEME_NAME\")"
```

Emacs is the final consumer of a pipeline it does not control, on a distribution
whose entire claim is that Emacs is the desktop. That is the inversion this
document removes.

This is not a cosmetic re-org. Two concrete defects fall out of the current
arrangement, and both were found by reading it rather than by hitting them:

- **`swaylock` never follows a runtime switch.** `swaylock.nix` renders its
  config from the *build-time* `emanix.theme` via `home.file`. After
  `dot-theme-set high-contrast-light`, the lock screen is still whatever the
  flake was built with. The module says nothing about this; it is drift, not a
  decision. Contrast `firefox.nix`, which is equally build-time-only and says so
  in six lines of comment — that one is deliberate and stays.
- **A fresh machine is half-themed.** Only ghostty is seeded, by a bespoke
  `home.activation.seedGhosttyTheme` hook. btop, zellij, gtk, pi and Claude get
  nothing until someone runs a switch by hand. Nobody notices because running
  `dot-theme-set` is the first thing anyone does on a new box.

## The shape of the change

| Concern | Today | After |
| --- | --- | --- |
| `active-theme` / `last-<variant>` state | `dot-theme-set` writes | `emanix/theme-set` writes |
| Emacs colours | Emacs, called last as a client | Emacs, first-class |
| ghostty / btop / zellij symlinks | bash | Emacs |
| gsettings (gtk) | bash | Emacs, attempted and tolerated |
| swaylock | nothing — frozen at build time | Emacs |
| pi + Claude settings JSON | Python heredocs inside bash | two scripts, invoked by Emacs |
| `dot-theme-set` | 228-line orchestrator | `exec emacsclient -e`, plus `--list` |
| `dot-theme-toggle` | 77 lines nothing binds | `exec emacsclient -e`, and bound to `C-c v` |

Build time is unchanged and stays the single source of colour: `lib/themes.nix`
defines the palettes, `lib/theme-tree.nix` generates
`$EMANIX_THEMES_DIR/<name>/{colors.toml,gtk.conf,btop.theme,variant,emacs-theme,pi-agent-theme.json}`.
Nothing in this design touches how colours are *derived* — only who applies them
at runtime.

## Decisions taken

**Emacs is reachable on every host, so the authority can move without a
fallback path.** `emacs-daemon.nix` gives every non-EWM host a systemd user
daemon with `startWithUserSession = true`, and on EWM hosts Emacs *is* the
compositor. There is no machine in this fleet where `emacsclient` is absent by
design. This is what makes the inversion safe: "you need Emacs running to change
your theme" is not a new constraint on a distribution where Emacs not running
means there is no session. Rejected: keeping a reduced standalone bash path for
the no-Emacs case — that preserves exactly the duplication this removes, and
leaves two writers of `active-theme` with no owner.

**The two JSON patchers stay out-process.** Each is ~40 lines doing an atomic
replace with mode preservation and symlink resolution, and their comments record
two bugs they have already caused in this repo: a silently dropped exec bit, and
a `os.replace()` onto a symlink that severed a file's link to version control.
Reimplementing that in elisp re-solves a solved problem, and would put a JSON
round-trip of Claude Code's live settings file inside the Emacs that is the
desktop. They move from unreachable heredocs into
`dotfiles/bin/dot-theme-apply-pi` and `dotfiles/bin/dot-theme-apply-claude`,
where they become independently runnable and shellcheckable. Emacs orchestrates;
it does not absorb.

**Startup converges only when state is missing.** `emanix/theme-init` applies the
full switch when `active-theme` is absent or names a theme no longer in the
tree, seeded from the build-time `emanix.theme`; otherwise it loads the Emacs
theme and stops. Rejected: applying everything on every Emacs start. That is
attractive — it is `nixos-rebuild switch`'s own idempotent re-base logic applied
to the theme — but it rewrites `~/.claude/settings.json` at every login, and
that file is rewritten by Claude Code at runtime. `dot-theme-set` already
carries a comment about racing it. Repeating the write when nothing changed buys
nothing and widens the race. Rejected also: leaving startup as-is, which is what
produces the half-themed fresh machine above.

**No GUI detection in elisp; the gtk step is attempted and tolerated.** An
earlier draft said `emanix-theme--apply-gtk` would be a no-op unless
`emanix.gui`. Emacs cannot see that option — it is a Nix value, and the obvious
bridges do not hold. A `EMANIX_GUI` session variable would be unreliable in
exactly the case that matters: the EWM Emacs is started by a system unit and
does not inherit the shell's environment, which is why `$EMANIX` was found unset
in rafik's live session on 2026-09-10. `display-graphic-p` is no better, since a
daemon with no frames yet reports nil on a GUI host. So the step runs
unconditionally and its failure is reported and swallowed — which is what the
bash does today with `2>/dev/null || true`, and is already required by the
failure discipline below. Nothing is lost: on a headless host the call fails,
and a headless host has no GTK to theme.

**`C-c v` binds the toggle**, for "variant" — the thing it flips. Rejected:
`C-c T`, which pairs more prettily with `C-c t` (ghostel) but is invisible to
`checks/welcome-keys.nix`: that guard extracts `C-[a-z] [a-z?]` and its own
comment states an uppercase row "will NOT be extracted at all, and this guard
will not see it". A lowercase key is a guarded key.

**No super-key binding yet.** `s-i` exists for arc because a `C-c` prefix cannot
reach Emacs from a focused Wayland surface — the follow-up key goes to the
surface — and the same limitation applies to toggling the theme from a slot
running Firefox. That is a real gap, but intercepted keys are scarce and this
command has no usage history. Revisit once it has one.

**`~/.config/dotfiles/` is NOT renamed.** It is a stow-era name in a
distribution that is not called dotfiles, and it reads worse once Emacs owns
what is inside it. But it is referenced from `zsh.nix` (which exports
`ACTIVE_THEME` from it), from `emanix-theme.el`, and from the manual; folding a
path rename into an authority inversion means a post-change failure could be
either cause. Worth doing, separately.

**Firefox stays build-time-only.** `firefox.nix` states it deliberately:
"Running `dot-theme-set` does not change Firefox at all, on restart or ever;
only editing `emanix.theme` and rebuilding does." That is a decision on the
record, unlike swaylock's silence. Not relitigated here.

## Module structure

`emanix-theme.el` today is entirely "do". Applying six more side-effects through
that shape is untestable, so the switch splits into a decision and its
execution.

```
emanix-theme--plan (name)        -> plist, or nil for an unknown theme
emanix-theme--apply-links  (plan)   ghostty, btop, zellij, swaylock
emanix-theme--apply-gtk    (plan)   gsettings; failure tolerated
emanix-theme--apply-emacs  (plan)   the existing load-theme logic, unchanged
emanix-theme--reload-apps  ()       pkill -SIGUSR2 ghostty
emanix/theme-set     (name)         plan -> steps -> consumer hook
emanix/theme-toggle  ()             counterpart variant -> theme-set
emanix/theme-init    ()             converge if state missing, else load only
```

`emanix-theme--plan` returns the whole switch as data: theme directory, variant,
Emacs theme symbol, the symlink source/target pairs, and the gtk key/value
pairs. It writes nothing. This is what the tests assert against, and it is why
an unknown theme name can be rejected before a single file is touched.

`emanix/theme-palette-color` is unchanged. It is already the public palette read
path and `emanix-prose.el` depends on it; nothing in this design gives Emacs a
second way to read a colour.

One existing constant has to become configurable. `emanix-theme--state-file` is
a `defconst` hardcoded to `~/.config/dotfiles/active-theme`, which was harmless
while Emacs only read it. Once Emacs *writes* it, a test that exercises the
switch would write into the real state directory. It becomes
`emanix/theme-state-dir`, a defcustom defaulting to `~/.config/dotfiles`, with
`active-theme` and `last-<variant>` resolved beneath it. This is the minimum
needed to make the tests honest; it is not the rename discussed under
"Decisions taken" — the default value is unchanged.

## The consumer hook

```elisp
(defcustom emanix/theme-apply-functions nil
  "Functions run after a theme switch, called with the plan plist.")
```

Same shape and the same error discipline as `emanix/modeline-extra-segments`
(added 2026-09-10): a consumer function that signals is logged and dropped, not
propagated.

This is what keeps the distro/consumer boundary intact. pi and Claude Code are
`scott.*` — declared in dotfiles, personal, and invisible to the distribution by
the same rule that ejected mu4e and ecomms. The distro registers the side
effects for things it installs (ghostty, btop, zellij, swaylock, gtk); the
consumer's `personal.el` registers one function that calls the two scripts.

## Failure discipline

`emanix/theme-set`'s existing docstring already states that it must never signal
to its caller, because it runs early in `init.el` on the host where Emacs is the
desktop and an uncaught error there costs the rest of init — not merely the
wrong colours. That constraint now covers six more side-effects, so each step is
wrapped individually rather than the function as a whole:

- one failing symlink must not cost the Emacs theme
- a missing `gsettings` on a headless box must not abort the switch
- a consumer hook function that signals must not stop the ones after it

Failures are collected and reported with `message`. The return value stays the
theme symbol actually enabled, or nil — unchanged, so existing callers keep
working.

## swaylock

Gets the pattern `ghostty.nix` already uses and proved: pre-render every palette
to `~/.config/swaylock/themes/<name>.conf` at build time, and let the switch
symlink one into place.

The load-bearing half is that `swaylock.nix` must **stop declaring
`~/.config/swaylock/config` as `home.file`**. `ghostty.nix` documents the trap
directly: a runtime path with two owners gets renamed to `.hm-bak` by Home
Manager at every activation, silently reverting the active theme on the next
rebuild. The same failure is waiting for swaylock the moment the switcher starts
writing there.

## Tests

ERT in batch — no dbus, no systemd, no gateway — wired as a new
`checks/theme-switch.nix` on the emanix flake, following
`checks/agent-shell-sync.nix`:

- `--plan` against a fixture theme directory: variant, emacs-theme symbol, and
  the full link set
- `--plan` for an unknown theme returns nil, and nothing is written
- toggle uses the counterpart marker; falls back to the first theme of the
  opposite variant; fails cleanly when there is none
- `theme-init` applies the full switch when state is absent, and only loads the
  theme when state is present and valid
- the hook is called with the plan, and a signalling hook function is logged
  without aborting the steps after it
- a failing `gsettings` is reported and does not abort the steps after it

Side effects are stubbed with `cl-letf` over `call-process` and
`make-symbolic-link`, asserting the commands and link pairs — the pattern the
cpgw tests established on 2026-09-10. The tests must not touch
`~/.config/dotfiles/`; the state directory is a parameter with a temp-dir
default under test.

## Ledger

| | Deleted | Added |
| --- | --- | --- |
| `bin/dot-theme-set` | ~190 of 228 lines | — |
| `bin/dot-theme-toggle` | ~70 of 77 lines | — |
| `ghostty.nix` | `home.activation.seedGhosttyTheme` | — |
| `swaylock.nix` | the `home.file` config | per-palette render |
| `emanix-theme.el` | — | ~180 lines |
| dotfiles `bin/` | 2 embedded heredocs | 2 scripts |
| tests | — | ~120 lines + one flake check |

Net line count is close to flat. The win is not fewer lines; it is one owner for
the runtime theme, two latent defects closed, and the switch becoming testable
for the first time.

## Rollout

Both repos change together, and dotfiles pins `emanix` from GitHub. So this has
the sequencing established on 2026-09-10 by the cpgw work:

1. emanix: mechanism, hook, swaylock, tests, check
2. commit and push emanix
3. dotfiles: `nix flake lock --update-input emanix`
4. dotfiles: the two scripts, `personal.el` registration, the thinned wrappers
5. rebuild, then verify a real switch end to end

Steps 1 and 4 must not be split across a rebuild. A half-applied version of this
is a machine whose theme state has two writers and no owner — worse than either
end state. Local verification before step 2 uses
`--override-input emanix path:/home/scott/projects/emanix`, as the cpgw work did.

## Documentation to update

The theming manual is the large one and should be budgeted as real work, not a
trailing chore.

- **`~/docs/org/websites/emanix/pages/docs/theming.org`** — 304 lines, and
  `dot-theme-set` appears in about sixteen of them: the command table, the state
  directory table, the theme-tree listing, the ghostty and pi sections, the
  "adding a theme" walkthrough. It describes bash as the switcher throughout.
  This is the published manual at emanix.net and the only place the theming
  documentation lives.
  - Its "Known limitations" section ends with *"No keybinding for
    `dot-theme-toggle`. The Hyprland-era `$mod+Shift+T`…"*. This design closes
    that; the entry should be deleted rather than amended.
- `dotfiles/docs/manual/01-tools.md` — the `bin/` table rows for both scripts
- `dotfiles/docs/manual/03-roll-your-own.md` — the `dot-*` helper list
- `emanix-theme.el`'s own header, which opens by naming `bin/dot-theme-set` as
  the caller

While in those files: four places in dotfiles point at
`the Emanix manual's docs/manual/02-theming.md`
(`docs/manual/README.md:25`, `02-philosophy.md:115`, `01-tools.md:33`,
`01-tools.md:146-147`). No such file exists in either repo — the manual is
`theming.org` on the website. That drift is pre-existing and out of scope on its
own, but three of those four lines are ones this work edits anyway, so fixing
the pointer costs nothing here and leaves a stale cross-reference otherwise.
