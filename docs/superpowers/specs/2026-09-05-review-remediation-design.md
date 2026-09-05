# Whole-repo review remediation

**Date:** 2026-09-05
**Status:** design, decisions settled; not yet planned
**Scope:** cross-repo — `~/projects/emanix` and `~/dotfiles`
**Trigger:** whole-repo review requested before rafik's SSD-swap reinstall.

## Why this exists

A high-effort review of both repos found 15 substantive issues plus ~18 smaller
ones. Two endanger the reinstall itself and one was introduced the same day by
the hardware-layer work. This document is the durable record of what was found;
without it the findings live only in a transcript.

## The organising principle

Group by **when a defect bites**, not by which repo holds it. Reinstall day is
the deadline for one group and irrelevant to the others.

| Group | Bites when | Contents |
| --- | --- | --- |
| A | rafik's reinstall | 1-6 |
| B | already, silently, on running hosts | 7, 8, 11, 12, 13 |
| C | only if datacore is rebuilt from the flake | 9, 10 |
| D | never directly; cost is comprehension | 14, 15, comment drift, the tail |

## Decisions taken

**Fresh-host bootstrap (finding 4).** The installer copies the staged flake to
`~/dotfiles` during the install. The ISO already stages the consuming repo at
`/etc/emanix/flake` — it is what the install is built FROM — so this needs no
network, no SSH key and no credentials on a machine that has none yet. That
covers `bin/` (on PATH via `EMANIX_BIN_DIR`) and the flake checkout. The emanix
checkout that `liveElisp` points at still needs a clone; `emanix-firstboot`
offers it once the tailnet is up, and says plainly what breaks until then.
Rejected: setting `liveElisp = false` in dotfiles (loses live elisp editing,
which the whole Emacs workflow depends on) and cloning both repos over the
network at first boot (needs credentials that do not exist yet).

**Docker (finding 15).** Removed as a fleet-wide default, and the primary user
is no longer added to the `docker` group unconditionally. whistle and datacore
opt in explicitly; rafik loses a daemon, a bridge and a root-equivalent group
it never used. NOT inert — rafik's closure shrinks, deliberately.

## Group A — reinstall blockers

**1. The wipe confirmation can name a disk disko never touches.** *Critical.*
`installer/fresh-emanix-install:505` cross-checks the target against
`$REPO/ioshi/hi-hardware/disko/$FLAKE_HOST.nix`. The 2026-09-05 hardware-layer
work deleted `disko/rafik.nix` and moved rafik's layout inline into
`dotfiles/flake.nix`, so the grep finds nothing, `|| true` swallows it,
`$declared` is empty and the mismatch warning cannot fire. Compounding it,
`:552` runs `disko --mode destroy,format,mount --flake "$FLAKE_REF"` and never
passes `$DISK` — so `resolve_disk`, the `lsblk` display and
`Type 'yes' to wipe $DISK` all describe a device disko may not touch. Fix:
resolve the declared device with
`nix eval "$REPO#nixosConfigurations.$FLAKE_HOST.config.disko.devices.disk.main.device"`
and make a mismatch FATAL rather than a warning.

Note for the record: the hardware-layer change was proved inert by drvPath
equality, and that proof was sound — for the built system. It could not see a
shell script in another repo that greps for a file path. Structural coupling
that crosses a repo boundary is invisible to closure comparison.

**2. An empty username sets root's password.** *High.*
`:617` derives `USERNAME` from `ls /home | head -1`, prompts once with no
re-prompt, then runs `nixos-enter --root /mnt -c "passwd $USERNAME"`. A stray
Enter runs `passwd` bare in the chroot, setting **root's** password while the
real account — created `--no-root-password` and with no password of its own —
stays passwordless, and the script prints success. `$USERNAME` is also
unquoted into a `bash -c` string, and the bare command substitution under
`set -e` kills the installer after a successful `nixos-install`.

**3. A failed install cannot be retried.** *High.* No `trap`, no `umount`, no
`cryptsetup close` anywhere in 635 lines (verified: zero matches). If
`nixos-install` fails the run exits with the disk partitioned, LUKS open as
`cryptroot` and `/mnt{,/boot,/home,/nix}` mounted. Retrying is worse than
useless: `resolve_disk:112` skips any device with mounted partitions, so the
target goes invisible and the next run dies at `preflight failed: disk`.

**4. A fresh host boots to no Emacs config and no `bin/`.** *High.*
`emanix.src.liveElisp` defaults true and dotfiles overrides it nowhere, so
`~/.config/emacs/{init,config,fallback}.el` and `lisp/` are out-of-store
symlinks into `~/projects/emanix`, which nothing creates. `EMANIX_BIN_DIR`
(`~/dotfiles/bin`, on PATH) is equally absent. And the runbook lies:
`dotfiles/docs/ioshi/emanix-install.md:113` says `emanix-firstboot` "prints the
Syncthing device id… clones the repo to `~/dotfiles`, and confirms
`~/.pi/agent/auth.json` decrypted" — `firstboot.sh` has zero matches for git,
clone, syncthing or auth.json. It joins the tailnet and stops. The runbook is
what gets followed on the day, so it is part of the fix.

**5. rafik's disk layout is written twice.** *High.* `dotfiles/flake.nix:193`
and `:292` both spell the same `emanix.lib.mkDisk` call, kept in step by a
comment. Introduced 2026-09-05. A `let rafikDisk = …; in` makes the invariant
structural. This is the partition table for the machine being reinstalled.

**6. The EWM flap marker survives reboots.** *High.* `ewm.nix:146` sleeps a
fixed 2 s then checks for the daemon; a cold first boot after a reinstall is
the slowest boot there is, so the check can fire before Emacs appears, elapsed
lands under 15 s and `touch /tmp/.ewm-flap` runs. `boot.tmp.cleanOnBoot` is set
nowhere in either repo (NixOS default false), so the marker persists and the
desktop stays shell-only until someone reads the tty1 message and deletes it by
hand. Fix: put the marker in `$XDG_RUNTIME_DIR`, and wait for the daemon rather
than sleeping.

## Group B — already breaking, silently

**7. `calendar-sync` corrupts Dates.org and multiplies events.** *High.*
`calendar_sync.py:226` — `cmd_push` parses once (`:314`) then calls
`add_property_to_entry` per entry, which re-reads and rewrites the whole file
while the caller still holds `entry.line_start` from the first read; the drawer
is also inserted after the timestamp line. Reproduced: entry one gets three
nested drawers, entries two and three none, the file stops being valid org, and
because `parse_org` only looks for a drawer BEFORE the timestamp the next run
sees zero mappings and creates fresh Google events for every heading. Every
sync multiplies the calendar. `cmd_pull:391` has the same defect. `config.el:592`
binds it to `C-c c` with a nil output buffer, so none of it is visible.

**8. `bin/firefox` shadows the real firefox.** *High.* The wrapper probes only
`/usr/bin/firefox`, `/usr/bin/firefox-esr` and flatpak. All three hosts are
NixOS. emanix installs Firefox to `/etc/profiles/per-user/scott/bin/firefox`,
and `zsh.nix:58` prepends `$EMANIX_BIN_DIR` to PATH so the wrapper wins.
Confirmed on rafik: `zsh -i -c 'firefox --version'` → `no browser binary found`,
exit 127. `emanix-ewm-slots.el:18` falls back to the same wrapper.

**11. `network-online.target` does not exist in the user manager.** *Medium.*
Verified live. `weekly-report.nix:135` and `i-intelligence/syncthing.nix:66`
order against it; `Wants=` on an unloadable unit is non-fatal, so both
orderings fail silently in exactly the way their comments say they prevent.
Worst for weekly-report: `Persistent=true` + `RandomizedDelaySec=5m` means the
catch-up run fires minutes after a WSL start and `claude -p` dies on its first
API call.

**12. `ib up` reports failure on success.** *Medium.* `ibgateway.nix:120` —
`ibCli` is a `writeShellApplication` (injects `set -euo pipefail`) and line 120
starts two units unguarded, unlike the `down`/`status` branches which guard.
Those unit names exist nowhere in either repo — hand-installed on the live
rafik, so they vanish at reinstall.

**13. Two installer tests are unconditionally green.** *Medium.*
`tests/installer-modes.sh:47-62` greps output for `usage:` and
`unknown host\|not found in the flake`; neither string appears anywhere in the
installer. Both tests would stay green if it crashed on line 1. Separately
`bin/dot-doctor:47` degenerates to `[[ -d "/" ]]` when `EMANIX_THEMES_DIR` is
unset and the marker file is missing — the one check that would report an
unwired theme system fails open — and `:37`/`:44`/`:45` test for apt,
`/usr/bin/firefox` and a Debian font path, so `dot-doctor` exits 1 on every
host and its ✗ lines have been trained to be ignored.

## Group C — datacore disaster recovery

**9. A rebuilt datacore exposes unauthenticated services on the tailnet.**
*High.* `datacore/configuration.nix:178,205` open syncthing 8384 (on
`tailscale0` and every `br-+` docker bridge) and backrest 9898. The comments
state both are safe only because they are password-protected, and equally state
that the credentials in `secrets/{syncthing-gui-auth,backrest-auth}.age` are
deliberately NOT declared as `age.secrets` — they are applied to runtime state.
So a datacore rebuilt from the flake rather than restored comes up with a
regenerated `config.xml`, no GUI auth, and fleet-hub config control open to
every tailnet node.

**10. A rebuilt datacore takes no backups.** *High.* `:361` and `:398`
`ExecStart` scripts under `/home/scott/projects/datacore-config/bin/`, and
`:232` reads `/home/scott/.config/backrest/config.json`. Nothing in either
flake, in syncthing's folder set, or in the installer creates any of them. Both
timers fire nightly into `203/EXEC`, backrest starts with no repo and no plan,
and the health check whose job is to notice is the other unit that cannot start.

## Group D — simplification and drift

**14. 244 lines of inline KDL in `zellij.nix:81-325`**, two theme blobs. Applying
`0↔15, 7↔8` to the dark half yields the light half byte-for-byte, and
`lib/themes.nix:168 ansiSlots` already implements that swap for every other
themed app. The same file reads its other KDL from `./zellij/*.kdl` via
`renderKdl` nine lines above. ~12 lines of work.

**15. Docker.** See Decisions. Related: `emanix/flake.nix:178-186` runs
`role-workstation`, `role-server` and `role-wsl` checks that now evaluate
IDENTICAL systems (`emanix.role` is read by exactly one line, `zsh.nix:46`),
justified by a comment describing role profiles deleted on 2026-08-30.

**Comment drift.** 37% of emanix's Nix lines and 40% of dotfiles' are pure
comment (`firmware.nix` 83%, `emanix.nix` 78%). Confirmed-false statements found
without hunting: `theme.nix:99` names `dotfilesLib` (exists in neither repo);
`packages.nix:9` says packages "stay under apt for Phase 1"; `mpv.nix:238` cites
a `lib.optional` that `packages.nix:56` says was removed; `ewm.nix:166` says
XWayland starts in `loginShellInit`, which it does not; `themes.nix:8` documents
a `lib.theme.generators` attribute that does not exist; `swaylock.nix:11` points
at `modules/nixos/ewm.nix`, a path that does not exist; `zsh.nix:45` says nothing
reads `EMANIX_ROLE` while `theme.nix:36` says consumers do; `btop.nix`, `lf.nix`
and `mpv.nix` cite a `base/…` stow layout that is gone; `home/scott/default.nix:143`
says `mkForce` is needed "because the distro sets it plainly" while
`emanix/flake.nix:100` uses `mkDefault`; `hosts/rafik/configuration.nix:25`
justifies a NOPASSWD `nixos-rebuild` rule (a full root escalation, despite the
comment claiming tight scoping) by "elisa's rebuilds" — elisa is retired and
nothing calls `nixos-rebuild`. The README is accurate by contrast. The repo
already wrote the lesson for itself at `emacs/packages.nix:13`: "a pin that
hardcodes an ELPA URL has an expiry date nobody writes down". Prose has one too.

### Tail

`config.el:596` `C-c c` calls `start-process-shell-command` with 4 args (arity
`(3 . 3)`) — the advertised binding has never worked. `personal.el:22`
after-save date-stamper signals `Invalid search bound` on any org file with a
heading, and in the no-heading path clobbers the kill-ring and leaves the buffer
modified after save. `config.el:103` `auto-revert-use-file-system-watcher` is not
a variable in any Emacs (it is `auto-revert-use-notify`), and
`auto-revert-interval` is `setq`'d after the mode is on so its `:set` never runs
— the timer is 5 s, not 1. `emanix-modeline.el:171` calls `redraw-display` every
3 s inside the compositor plus a synchronous `nmcli` shell-out its own docstring
twelve lines above forbids. `emanix-ewm.el:87` hardcodes rafik's two monitors in
the distribution layer. `calendar_sync.py:112,140` writes the OAuth client secret
and refresh token 0644. `iso.nix:130` is the only script using
`writeShellScriptBin` rather than the shellchecked `writeShellApplication` that
`init.nix` and `firstboot.nix` both use — and it is the disk-wiping one.
`fresh-emanix-install:350` `grep -qx` treats the hostname as a regex (`rafi.`
matches `rafik`); wants `-qxF`. `hp-15-ef2013dx.nix:50` re-declares filesystems
disko generates; `disko/datacore.nix` should be `mkDisk` with `extraSubvolumes`,
removing ~60 lines (Gate 1 already proved the layout reproduces at 2522 bytes).
`net/syncthing.nix:26` + `i-intelligence/syncthing.nix:80` hold the datacore
device ID as a literal in two files that must be edited together, and it has
changed once already. `whistle/configuration.nix:242` `pearl-platform-db` reads a
hand-placed `/var/lib/pearl-db/env` nothing creates. `bin/minne:3` unguarded `cd`
plus an `LD_LIBRARY_PATH` store path already garbage-collected on whistle.
`bin/calendar-sync:7` interpolates `$*` unquoted into `nix-shell --run`.
`fallback.el:172` EWM binding block copy-pasted from `config.el:857`.
`lib/disk.nix:37` `device` is the one destructive argument the file does not
validate. `packages.nix:5,122` structure is contorted to keep a derivation hash
byte-stable, which is not a property worth shaping source around.

## Out of scope

- Anything requiring rafik to be reinstalled first (Task 7 of the hardware-layer
  plan remains gated on the SSD).
- Rotating the datacore credentials referenced in Group C — declaring them is in
  scope; changing their values is not.
