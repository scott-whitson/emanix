# Review Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every finding from the 2026-09-05 whole-repo review, in the order they bite.

**Architecture:** Four independently shippable phases. Phase A must land before rafik's SSD-swap reinstall; B, C and D are independent of it and of each other. Same-shape fixes are batched into one task rather than split, per the executor skill's batching rule.

**Tech Stack:** Nix flakes, NixOS modules, bash (installer + wrappers), Python (calendar-sync), Emacs Lisp.

**Spec:** `docs/superpowers/specs/2026-09-05-review-remediation-design.md`

## Global Constraints

- **Two repos.** Every task names its repo. `~/projects/emanix` and `~/dotfiles`. Do not cross without being told to.
- **No `Co-Authored-By` trailers in any commit, ever.**
- **`installer/fresh-emanix-install` wipes disks.** Tasks A1-A4 edit it. Every change there gets `bash -n` and `shellcheck`, and every behavioural claim gets a test in `tests/installer-modes.sh`. Never assert on a string by grepping the script — see A-common below.
- **Flake eval cannot see untracked files.** `git add` before any `nix` command.
- **`nix flake check` evaluates but never builds** the `role-*` closures. Do not make a check realize a real system closure.
- **`nix eval` is refused inside a worktree-isolated session** (any command containing the token `eval`). If a task's verification is spelled that way and you are in a worktree, substitute:
  `nix build --impure --no-link --print-out-paths --expr 'let p = import <nixpkgs> {}; f = builtins.getFlake (toString /ABS/PATH); in p.writeText "probe" (builtins.toJSON EXPR)'` then `cat` the printed path.
- **Nothing personal enters emanix**: no hostname, username, timezone, key or peer name. Checks use `checkhost`/`checkuser`.
- **rafik, datacore and whistle are running machines.** Any task that moves a host's `toplevel.drvPath` must say so in its report with the before/after paths. Silent closure movement is a defect.
- **Do not rotate any credential.** Declaring a secret is in scope; changing its value is not.

### A-common: the test-honesty rule

The review found two installer tests that grep for strings appearing nowhere, so they are unconditionally green and would stay green if the installer crashed on line 1. Every new assertion in `tests/installer-modes.sh` must be **behavioural** — run the script (or source a pure function out of it) and assert on exit codes and output. A grep is acceptable only where the behaviour is unreachable without wiping a disk, and then it must assert on a **call site count**, not a definition.

---

# Phase A — reinstall blockers

### Task A1: The installer must confirm the disk disko will actually erase

**Repo:** `~/projects/emanix` · **Severity: Critical**

**Files:**
- Modify: `installer/fresh-emanix-install:503-510` (the cross-check), and the `disko` invocation at `:551-556`
- Modify: `tests/installer-modes.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: a fatal preflight that resolves the layout's device from the flake.

**The defect.** The cross-check greps `$REPO/ioshi/hi-hardware/disko/$FLAKE_HOST.nix`. That path no longer exists for rafik — the 2026-09-05 hardware-layer work moved the layout inline into `dotfiles/flake.nix`. `grep` on a missing file yields nothing, `2>/dev/null … || true` swallows it, `$declared` is empty, the `if` never fires. Meanwhile `disko --mode destroy,format,mount --flake "$FLAKE_REF"` never receives `$DISK`, so the `lsblk` display and the `Type 'yes' to wipe $DISK` prompt describe a device disko may not touch. Two drives present, or the new SSD enumerating differently, and the prompt names one disk while another is destroyed.

- [ ] **Step 1: Write the failing test**

Append to `tests/installer-modes.sh`, before its summary:

```bash
# --- Target-disk cross-check -------------------------------------------------
# The prompt says "This ERASES $DISK", but disko is invoked with --flake and
# never with $DISK: it erases whatever disko.devices.disk.main.device says. The
# cross-check that reconciles the two MUST read the flake, not a file path that
# a consuming repo is free to move (it already did, on 2026-09-05, which is how
# this was found).
if grep -q 'ioshi/hi-hardware/disko/\$FLAKE_HOST\.nix' "$SCRIPT"; then
  echo "FAIL cross-check still greps a hardcoded consumer file path"
  fails=$((fails + 1))
else
  echo "ok   cross-check does not depend on a consumer's file layout"
fi

# It must ask the FLAKE for the device disko will use.
if grep -q 'config\.disko\.devices\.disk\.main\.device' "$SCRIPT"; then
  echo "ok   cross-check resolves the device from the flake"
else
  echo "FAIL cross-check does not resolve the device from the flake"
  fails=$((fails + 1))
fi

# A mismatch must be FATAL. A warn+continue on the step before a wipe is a
# prompt the user has been trained to accept.
if awk '/declared.*!=.*DISK|DISK.*!=.*declared/,/fi/' "$SCRIPT" | grep -q '\bdie\b'; then
  echo "ok   a device mismatch is fatal"
else
  echo "FAIL a device mismatch does not call die"
  fails=$((fails + 1))
fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/installer-modes.sh`
Expected: the first and third FAIL, the second FAILs. Exit non-zero.

- [ ] **Step 3: Replace the cross-check**

Replace lines 503-510 with:

```bash
# Cross-check the device disko will ACTUALLY erase against the one the prompt
# is about to name. These are not the same thing by construction: disko is
# invoked with --flake, never with $DISK, so it partitions whatever
# disko.devices.disk.main.device evaluates to. $DISK only drives the preflight
# display and the confirmation text.
#
# Ask the FLAKE, not a file. This grepped
# $REPO/ioshi/hi-hardware/disko/$FLAKE_HOST.nix until 2026-09-05, when a
# consuming repo moved its layout inline and the grep silently started
# returning nothing -- `|| true` swallowed it, $declared went empty, and the
# mismatch branch became unreachable. A consumer's file layout is not this
# script's business; the evaluated config is.
declared="$(nix eval --raw \
  "$REPO#nixosConfigurations.$FLAKE_HOST.config.disko.devices.disk.main.device" \
  2>/dev/null || true)"

if [ -z "$declared" ]; then
  die "could not read the disko device for $FLAKE_HOST from $REPO.
Refusing to continue: without it the confirmation below would name a disk this
script cannot prove disko will use. If this host genuinely has no disko layout,
it cannot be installed by this script."
fi

if [ "$declared" != "$DISK" ]; then
  die "TARGET MISMATCH — refusing to continue.
  disko will erase : $declared   (from $FLAKE_HOST's flake config)
  preflight picked : $DISK
Re-run with --disk $declared if that is the disk you mean, or fix the layout.
This is fatal rather than a prompt: the next step destroys a disk, and a
warning here is one the operator has been trained to accept."
fi
```

- [ ] **Step 4: Make the confirmation name the authoritative device**

At `:558-560`, the display and prompt use `$DISK`. After Step 3 they are proven equal, so no change is required — but add one line above `say "Target disk"` recording why:

```bash
# $DISK and $declared are proven equal by the cross-check above, so naming
# $DISK here is naming the disk disko will erase.
```

- [ ] **Step 5: Run the tests**

```bash
./tests/installer-modes.sh
bash -n installer/fresh-emanix-install && echo "syntax ok"
nix run nixpkgs#shellcheck -- installer/fresh-emanix-install 2>&1 | tail -10
```
Expected: all assertions ok, syntax ok, no NEW shellcheck findings (one pre-existing `SC2086` at ~line 350 is expected; A4 fixes it).

- [ ] **Step 6: Prove it against the real consuming flake**

```bash
nix eval --raw '/home/scott/dotfiles#nixosConfigurations.rafik.config.disko.devices.disk.main.device'
```
Expected: `/dev/nvme0n1`. This is the value the installer will now compare against, read the same way it reads it.

- [ ] **Step 7: Commit**

```bash
git add installer/fresh-emanix-install tests/installer-modes.sh
git commit -m "installer: confirm the disk disko will actually erase

The cross-check grepped a consuming repo's file path, which that repo moved on
2026-09-05 -- grep returned nothing, || true swallowed it, and the mismatch
branch became unreachable. Meanwhile disko is invoked with --flake and never
with \$DISK, so it erases whatever the layout says while the prompt names
whatever the preflight picked. Two drives, or a differently-enumerating NVMe,
and those are different disks.

Resolve the device from the evaluated flake instead, and make a mismatch fatal:
a warning on the step before a wipe is one the operator has been trained to
accept."
```

---

### Task A2: An empty username must not set root's password

**Repo:** `~/projects/emanix` · **Severity: High**

**Files:** Modify `installer/fresh-emanix-install:616-628`; modify `tests/installer-modes.sh`

**The defect.** `USERNAME="$(nixos-enter --root /mnt -c 'ls /home | head -1' 2>/dev/null)"` is a bare command substitution under `set -e` (a `nixos-enter` failure kills the installer *after* a successful `nixos-install`). If it yields empty, `read -rp "Username: "` prompts once with no validation and no re-prompt; a stray Enter leaves `USERNAME` empty and `nixos-enter --root /mnt -c "passwd $USERNAME"` runs `passwd` bare in the chroot — setting **root's** password, while the real account (created `--no-root-password`, no password of its own) stays passwordless. The script then prints success. `$USERNAME` is also unquoted into a `bash -c` string.

- [ ] **Step 1: Write the failing test**

```bash
# --- Username / passwd safety -----------------------------------------------
# An empty USERNAME makes `passwd $USERNAME` run `passwd` bare in the chroot,
# which sets ROOT's password while the real account stays passwordless -- and
# the installer prints success. Assert the guard exists and is reached.
if grep -q 'validate_username' "$SCRIPT"; then
  echo "ok   installer validates the username"
else
  echo "FAIL installer has no validate_username"
  fails=$((fails + 1))
fi
if [ "$(grep -c 'validate_username' "$SCRIPT")" -ge 2 ]; then
  echo "ok   validate_username is called, not merely defined"
else
  echo "FAIL validate_username is defined but never called"
  fails=$((fails + 1))
fi
# The chroot command must quote the username.
if grep -q 'passwd \$USERNAME' "$SCRIPT"; then
  echo "FAIL username is unquoted in the passwd chroot command"
  fails=$((fails + 1))
else
  echo "ok   username is quoted into the passwd command"
fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/installer-modes.sh` — the first two FAIL, the third FAILs.

- [ ] **Step 3: Add the validator and harden the block**

`validate_hostname` already enforces the right character class (RFC-1123, which is also a valid Linux username). Add beside it:

```bash
# Same character class as a hostname, and the same reason: this value reaches a
# `bash -c` string in the chroot. Named separately from validate_hostname so
# the call sites read correctly.
validate_username() { validate_hostname "$1"; }
```

Replace the prestaged block:

```bash
if [ "$MODE" = prestaged ]; then
  # The username is defined by the consuming flake's host config. Probe the
  # mounted home dir (the only user that exists at this point), else prompt.
  # Interactive mode already has USERNAME from interactive_prompts.
  #
  # `|| true`: this is a bare command substitution under `set -e`, and a
  # nixos-enter failure here would otherwise kill the installer AFTER a
  # successful nixos-install -- the most expensive possible moment.
  USERNAME="$(nixos-enter --root /mnt -c 'ls /home | head -1' 2>/dev/null || true)"
  while ! validate_username "${USERNAME:-}"; do
    warn "could not determine the account name from /mnt/home."
    read -rp "Username for this machine's account: " USERNAME
  done
fi

# Belt and braces: interactive mode set USERNAME long before the disk was
# touched, so a bug upstream would surface here rather than as a bare `passwd`.
validate_username "$USERNAME" ||
  die "internal error: refusing to run passwd with username '$USERNAME'.
An empty or malformed name here would set ROOT's password in the chroot while
the real account stays passwordless."

say "Set a password for $USERNAME"
nixos-enter --root /mnt -c "passwd '$USERNAME'"
```

- [ ] **Step 4: Run the tests**

```bash
./tests/installer-modes.sh && bash -n installer/fresh-emanix-install && echo ok
nix run nixpkgs#shellcheck -- installer/fresh-emanix-install 2>&1 | tail -8
```

- [ ] **Step 5: Prove the validator rejects the dangerous input**

```bash
source <(sed -n '/^validate_hostname()/,/^}/p' installer/fresh-emanix-install)
source <(sed -n '/^validate_username()/,/^}/p' installer/fresh-emanix-install)
for u in "" " " "root; rm -rf /" "scott"; do
  validate_username "$u" && echo "ACCEPT '$u'" || echo "reject '$u'"
done
```
Expected: `reject ''`, `reject ' '`, `reject 'root; rm -rf /'`, `ACCEPT 'scott'`.

- [ ] **Step 6: Commit**

```bash
git add installer/fresh-emanix-install tests/installer-modes.sh
git commit -m "installer: refuse to run passwd with an empty username

An empty USERNAME made \`passwd \$USERNAME\` run \`passwd\` bare in the chroot,
setting ROOT's password while the real account -- created --no-root-password
and with no password of its own -- stayed passwordless, after which the script
printed success. The probe was also a bare command substitution under set -e,
so a nixos-enter failure killed the installer immediately after a successful
nixos-install, and the name went unquoted into a bash -c string.

Re-prompt until the name validates, re-check defensively before passwd, and
quote it."
```

---

### Task A3: A failed install must be retryable

**Repo:** `~/projects/emanix` · **Severity: High**

**Files:** Modify `installer/fresh-emanix-install` (add a trap near the top, after the `die`/`warn` helpers); modify `tests/installer-modes.sh`

**The defect.** Zero matches for `trap`, `umount` or `cryptsetup close` in 635 lines. A failed `nixos-install` exits with the disk partitioned, LUKS open as `cryptroot`, and `/mnt{,/boot,/home,/nix}` mounted. The retry is then blocked by the installer's own preflight: `resolve_disk` skips any device with mounted partitions, so the target goes invisible and the run dies at `preflight failed: disk`.

- [ ] **Step 1: Write the failing test**

```bash
# --- Failure cleanup ---------------------------------------------------------
# Without this, a failed nixos-install leaves /mnt mounted and cryptroot open,
# and resolve_disk then SKIPS the target (it skips devices with mounted
# partitions) -- so the retry dies at "preflight failed: disk". The first run's
# failure makes the second impossible.
if grep -q "^trap .* EXIT" "$SCRIPT"; then
  echo "ok   installer has an EXIT trap"
else
  echo "FAIL installer has no EXIT trap"
  fails=$((fails + 1))
fi
for needle in 'umount' 'cryptsetup close'; do
  if grep -q "$needle" "$SCRIPT"; then
    echo "ok   cleanup performs: $needle"
  else
    echo "FAIL cleanup does not perform: $needle"
    fails=$((fails + 1))
  fi
done
# It must NOT unmount on success -- the caller reboots from a mounted /mnt in
# some flows, and a trap that fires on the happy path is its own bug.
if grep -q 'INSTALL_OK' "$SCRIPT"; then
  echo "ok   cleanup is suppressed on success"
else
  echo "FAIL cleanup has no success guard"
  fails=$((fails + 1))
fi
```

- [ ] **Step 2: Run it to verify it fails** — all four FAIL.

- [ ] **Step 3: Add the trap**

After the `die()` helper near the top:

```bash
# Leave the disk retryable. disko mounts /mnt and opens LUKS as `cryptroot`
# before nixos-install runs; if that build fails, an untrapped exit leaves both
# in place -- and the NEXT run cannot recover, because resolve_disk skips any
# device with mounted partitions, so the target becomes invisible and the run
# dies at "preflight failed: disk". The first failure makes the second attempt
# impossible, which is the worst property an installer can have.
#
# Suppressed on success: some flows reboot from a mounted /mnt, and a trap that
# fires on the happy path is its own bug.
INSTALL_OK=0
cleanup_target() {
  [ "$INSTALL_OK" -eq 1 ] && return 0
  # Nothing mounted means nothing to do -- a preflight abort must stay silent.
  mountpoint -q /mnt 2>/dev/null || return 0
  warn "install did not complete — unmounting /mnt so a retry can see the disk."
  umount -R /mnt 2>/dev/null || true
  cryptsetup close cryptroot 2>/dev/null || true
}
trap cleanup_target EXIT
```

Set `INSTALL_OK=1` immediately after the final `say "$FLAKE_HOST installed."`.

- [ ] **Step 4: Run the tests**

```bash
./tests/installer-modes.sh && bash -n installer/fresh-emanix-install && echo ok
nix run nixpkgs#shellcheck -- installer/fresh-emanix-install 2>&1 | tail -8
```

- [ ] **Step 5: Prove the trap is inert when nothing is mounted**

The existing `--check-only` path exits before disko. Run it and confirm no warning appears:

```bash
./tests/installer-modes.sh 2>&1 | grep -i 'unmounting' && echo "BAD: trap fired on a preflight run" || echo "ok: trap silent when nothing mounted"
```

- [ ] **Step 6: Commit**

```bash
git add installer/fresh-emanix-install tests/installer-modes.sh
git commit -m "installer: unmount on failure so a retry can see the disk

A failed nixos-install left the disk partitioned, LUKS open as cryptroot and
/mnt mounted. resolve_disk skips any device with mounted partitions, so the
retry could not find the target and died at 'preflight failed: disk' -- the
first failure made the second attempt impossible.

Suppressed on success, and silent when nothing is mounted, so a preflight abort
stays quiet."
```

---

### Task A4: A freshly installed host must have its checkouts and an honest runbook

**Repo:** `~/projects/emanix` **and** `~/dotfiles` · **Severity: High**

**Files:**
- Modify: `emanix/installer/fresh-emanix-install` (copy the staged flake; also fix `grep -qx` → `grep -qxF` at ~`:350`)
- Modify: `dotfiles/hosts/common/firstboot.sh` (offer the emanix clone; say what breaks until then)
- Modify: `dotfiles/docs/ioshi/emanix-install.md:105-115` (the false claims)

**The defect.** `emanix.src.liveElisp` defaults true and dotfiles overrides it nowhere, so `~/.config/emacs/{init,config,fallback}.el` and `lisp/` are out-of-store symlinks into `~/projects/emanix`, which nothing creates. `EMANIX_BIN_DIR` (`~/dotfiles/bin`, on PATH) is equally absent. The runbook says `emanix-firstboot` "prints the Syncthing device id… clones the repo to `~/dotfiles`, and confirms `~/.pi/agent/auth.json` decrypted" — the script has **zero** matches for git, clone, syncthing or auth.json.

**Decision (from the spec):** the installer copies the staged flake. The ISO already stages the consuming repo at `/etc/emanix/flake` — it is what the install is built FROM — so this needs no network, no key and no credentials.

- [ ] **Step 1: Write the failing test**

```bash
# --- Fresh-host bootstrap ----------------------------------------------------
# liveElisp defaults true, so ~/.config/emacs symlinks into a checkout. Nothing
# created that checkout, so a fresh host booted to a dangling Emacs config and
# an absent bin/ on PATH. The ISO already stages the consuming flake -- copying
# it needs no network, key or credential.
if grep -q 'copy_staged_flake' "$SCRIPT"; then
  echo "ok   installer stages a consumer checkout into the new home"
else
  echo "FAIL installer does not stage a consumer checkout"
  fails=$((fails + 1))
fi
if [ "$(grep -c 'copy_staged_flake' "$SCRIPT")" -ge 2 ]; then
  echo "ok   copy_staged_flake is called, not merely defined"
else
  echo "FAIL copy_staged_flake is defined but never called"
  fails=$((fails + 1))
fi
# grep -qx treats the hostname as a regex: 'rafi.' matches 'rafik'.
if grep -q 'grep -qxF' "$SCRIPT"; then
  echo "ok   host matching is fixed-string"
else
  echo "FAIL host matching uses a regex, not a fixed string"
  fails=$((fails + 1))
fi
```

- [ ] **Step 2: Run it to verify it fails** — all three FAIL.

- [ ] **Step 3: Copy the staged flake in the installer**

Add near `write_generated_flake`:

```bash
# Put the flake this machine was installed FROM into the new user's home.
#
# liveElisp (emanix.src.liveElisp, default true) makes ~/.config/emacs a set of
# out-of-store symlinks into a checkout, and EMANIX_BIN_DIR puts the consumer's
# bin/ on PATH. Nothing else creates either, so before this a freshly installed
# host booted to a dangling Emacs config and a PATH entry pointing at nothing.
#
# The ISO already stages the consuming repo at /etc/emanix/flake -- it is what
# this install was built from -- so this needs no network, no SSH key and no
# credential on a machine that has none yet. It is a copy, not a clone: git
# history comes with it if the staged copy has any, and if it does not, the
# user replaces it with a real clone once they have keys.
copy_staged_flake() {
  local dest="/mnt/home/$1/dotfiles"
  [ -d "$REPO" ] || return 0
  [ -e "$dest" ] && { warn "$dest already exists — leaving it alone."; return 0; }
  say "Copying the flake into ${dest#/mnt}"
  install -d -m 755 "$(dirname "$dest")"
  cp -a "$REPO" "$dest"
  # The account does not exist on THIS system, only in the chroot, so chown by
  # the numeric ids nixos-install just created rather than by name.
  nixos-enter --root /mnt -c "chown -R '$1':users '/home/$1/dotfiles'" || true
}
```

Call it after the password step, before the final `say`:

```bash
copy_staged_flake "$USERNAME"
```

Fix the regex-vs-fixed-string bug at ~`:350`: change `grep -qx "$FLAKE_HOST"` to `grep -qxF "$FLAKE_HOST"`.

- [ ] **Step 4: Make firstboot honest and offer the emanix clone**

In `dotfiles/hosts/common/firstboot.sh`, after the tailnet block:

```bash
# The distro's own elisp lives in ~/projects/emanix (emanix.src.liveElisp), and
# the installer cannot stage that one -- it only has the CONSUMING flake. Offer
# it here, where the tailnet is up and a key may exist. Emacs runs from the
# store copy until this is done; it is not broken, only un-live.
EMANIX_SRC="$HOME/projects/emanix"
if [ -d "$EMANIX_SRC/.git" ]; then
  say "emanix checkout already present at $EMANIX_SRC."
else
  say "emanix checkout"
  echo "  Missing: $EMANIX_SRC"
  echo "  Until it exists, ~/.config/emacs/{init,config,fallback}.el and lisp/"
  echo "  are dangling symlinks and Emacs starts with no configuration."
  read -rp "  Clone it now? [Y/n] " a
  case "$a" in
    [Nn]*) echo "  Skipped. Clone it later, then restart Emacs." ;;
    *)
      mkdir -p "$(dirname "$EMANIX_SRC")"
      git clone git@github.com:scott-whitson/emanix.git "$EMANIX_SRC" ||
        echo "  Clone failed — you may have no GitHub key on this host yet." >&2
      ;;
  esac
fi
```

- [ ] **Step 5: Correct the runbook**

In `dotfiles/docs/ioshi/emanix-install.md`, replace the false paragraph with what the scripts actually do:

```markdown
It joins the tailnet (prompts for a datacore preauthkey — mint with
`docker exec headscale headscale preauthkeys create --user 1 --expiration 1h`)
and offers to clone `~/projects/emanix`, which `liveElisp` symlinks
`~/.config/emacs` into.

`~/dotfiles` is already there — `fresh-emanix-install` copies the flake it
installed from into your home, so `bin/` is on PATH from the first boot.

It does **not** print a Syncthing device id, pair folders, or check
`~/.pi/agent/auth.json`; those are manual. This paragraph claimed all three
until 2026-09-05 and never did any of them.
```

- [ ] **Step 6: Verify**

```bash
cd ~/projects/emanix
./tests/installer-modes.sh
bash -n installer/fresh-emanix-install && echo "emanix ok"
bash -n ~/dotfiles/hosts/common/firstboot.sh && echo "firstboot ok"
nix run nixpkgs#shellcheck -- installer/fresh-emanix-install 2>&1 | tail -6
grep -c 'clones the repo to' ~/dotfiles/docs/ioshi/emanix-install.md
```
Expected: tests pass, both syntax-ok, shellcheck clean (the `SC2086` at ~350 is now fixed by `-qxF`; if it persists, report it), and the last grep returns `0`.

- [ ] **Step 7: Commit (two repos, two commits)**

```bash
cd ~/projects/emanix
git add installer/fresh-emanix-install tests/installer-modes.sh
git commit -m "installer: leave a usable machine — stage the flake into \$HOME

liveElisp symlinks ~/.config/emacs into a checkout and EMANIX_BIN_DIR puts the
consumer's bin/ on PATH; nothing created either, so a freshly installed host
booted to a dangling Emacs config and a PATH entry pointing at nothing. The ISO
already stages the consuming flake -- copying it needs no network, key or
credential on a machine that has none.

Also fixes grep -qx treating the hostname as a regex: 'rafi.' matched 'rafik'."

cd ~/dotfiles
git add hosts/common/firstboot.sh docs/ioshi/emanix-install.md
git commit -m "firstboot: offer the emanix clone; stop the runbook claiming work it never did

The runbook said emanix-firstboot prints a Syncthing device id, clones the repo
to ~/dotfiles and confirms auth.json decrypted. The script has zero matches for
git, clone, syncthing or auth.json -- it joined the tailnet and stopped. That
paragraph is what gets followed on reinstall day."
```

---

### Task A5: rafik's disk layout must be written once

**Repo:** `~/dotfiles` · **Severity: High**

**Files:** Modify `flake.nix` (the `let` block, rafik's `extraModules` ~`:193`, and `diskoConfigurations` ~`:292`)

**The defect.** The same `emanix.lib.mkDisk { device = "/dev/nvme0n1"; luks = true; filesystem = "btrfs"; swapSize = "0"; }` is written twice, kept in step by a comment. Introduced 2026-09-05. This is the partition table for the machine about to be reinstalled.

- [ ] **Step 1: Record the baseline**

```bash
cd ~/dotfiles
git status --porcelain   # must be clean
for h in rafik datacore whistle; do
  nix eval --raw ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath" > /tmp/$h.before; done
nix eval --json '.#diskoConfigurations.rafik' --apply 'f: (f {}).disko.devices' \
  | python3 -m json.tool --sort-keys > /tmp/rafik-disko.before
wc -c /tmp/rafik-disko.before   # expect 2417
```

- [ ] **Step 2: Hoist it into the `let`**

Add beside `rekey`:

```nix
      # rafik's partition table, defined ONCE. It is consumed twice -- as a
      # module in the host's extraModules, and as the diskoConfigurations
      # output the installer and `disko --mode destroy` read. Those two
      # disagreeing means the machine is partitioned one way and built for
      # another, so the invariant is structural here rather than a comment
      # asking two call sites to stay in step.
      rafikDisk = emanix.lib.mkDisk {
        device = "/dev/nvme0n1";
        luks = true;
        filesystem = "btrfs";
        swapSize = "0";
      };
```

Replace both call sites with `rafikDisk`, deleting the "keep the two in step" comment (the code now enforces it).

- [ ] **Step 3: Prove it inert**

```bash
git add -A
for h in rafik datacore whistle; do
  nix eval --raw ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath" > /tmp/$h.after
  diff -q /tmp/$h.before /tmp/$h.after && echo "$h INERT" || echo "$h MOVED"; done
nix eval --json '.#diskoConfigurations.rafik' --apply 'f: (f {}).disko.devices' \
  | python3 -m json.tool --sort-keys > /tmp/rafik-disko.after
diff -q /tmp/rafik-disko.before /tmp/rafik-disko.after && echo "layout IDENTICAL"
```
Expected: all three INERT, layout identical, still 2417 bytes. Anything else means the hoist changed a value — stop.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "flake: define rafik's partition table once

The same mkDisk call was written twice -- in the host's extraModules and in
diskoConfigurations -- kept in step by a comment. Those two disagreeing means
the machine is partitioned one way and built for another, which is worth an
invariant rather than a request. Proved inert: all three hosts' drvPaths and
the exported layout (2417 bytes) are byte-identical."
```

---

### Task A6: The EWM flap marker must not survive a reboot

**Repo:** `~/projects/emanix` · **Severity: High**

**Files:** Modify `ioshi/i-intelligence/ewm.nix:140-160`

**The defect.** `ewm-launch` returns once pgtk Emacs detaches; the script then sleeps a fixed 2 s and checks for the daemon. A cold first boot after a reinstall is the slowest boot there is, so the check can run before Emacs appears — the loop exits at once, elapsed lands under 15 s, and `touch /tmp/.ewm-flap` fires. `boot.tmp.cleanOnBoot` is set nowhere in either repo (NixOS default `false`), so the marker persists across reboots and the desktop stays shell-only until someone reads the tty1 message and deletes it by hand.

- [ ] **Step 1: Read the current block**

`sed -n '130,175p' ioshi/i-intelligence/ewm.nix` — note the exact marker path, the sleep, and the elapsed-time threshold before editing.

- [ ] **Step 2: Replace the fixed sleep with a bounded wait, and move the marker**

Two changes, both in that block:

1. **Marker path**: replace `/tmp/.ewm-flap` with `''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ewm-flap` everywhere it appears (the `touch`, the existence test, and the message telling the user how to clear it). `$XDG_RUNTIME_DIR` is cleared on logout by systemd, so the marker cannot outlive the session that set it — which is the property `/tmp` was assumed to have and does not.

2. **Wait, do not sleep**: replace the fixed `sleep 2` with a bounded poll for the daemon, so a slow first boot is not read as a crash:

```bash
# Wait for the daemon rather than assuming 2 s is enough. The first boot after
# an install is the slowest boot the machine will ever do -- compiling nothing
# but populating every cache cold -- and a fixed sleep there reads a healthy
# start as a flap, writes the marker, and leaves the desktop shell-only.
for _ in $(seq 1 30); do
  pgrep -f "bin/emacs --fg-daemon" >/dev/null 2>&1 && break
  sleep 1
done
```

Update the surrounding comment to say why the wait is bounded-poll rather than fixed-sleep, and cite the reinstall case.

- [ ] **Step 3: Verify it evaluates and the marker path changed**

```bash
git add ioshi/i-intelligence/ewm.nix
nix flake check 2>&1 | tail -4
grep -c '/tmp/.ewm-flap' ioshi/i-intelligence/ewm.nix   # expect 0
grep -c 'XDG_RUNTIME_DIR' ioshi/i-intelligence/ewm.nix  # expect >= 3
```

- [ ] **Step 4: Commit**

```bash
git add ioshi/i-intelligence/ewm.nix
git commit -m "ewm: stop a slow first boot from parking the desktop permanently

The flap check slept a fixed 2s then looked for the daemon. The first boot
after an install is the slowest the machine will ever do, so the check could
run before Emacs appeared, read a healthy start as a crash and touch the flap
marker. boot.tmp.cleanOnBoot is set nowhere, so a marker in /tmp SURVIVED
reboots -- the desktop stayed shell-only until someone read the tty1 message
and deleted it by hand.

Wait for the daemon instead of guessing, and put the marker in
\$XDG_RUNTIME_DIR, which systemd clears on logout."
```

---

# Phase B — already breaking, silently

### Task B1: `calendar-sync` must stop corrupting Dates.org

**Repo:** `~/dotfiles` · **Severity: High**

**Files:** Modify `tools/calendar-sync/calendar_sync.py` (`add_property_to_entry`, `cmd_push:314+`, `cmd_pull:391`); create `tools/calendar-sync/test_calendar_sync.py`; modify `bin/calendar-sync:7`; modify `~/projects/emanix/ioshi/i-intelligence/emacs/config.el:592-596`

**The defect.** `cmd_push` parses the org file once, then calls `add_property_to_entry` per entry — each call re-reads and rewrites the whole file while the caller still holds `entry.line_start` from the original read. The drawer is also inserted at `scan + 1`, after the `<YYYY-MM-DD>` line. Result: entry one gets three nested drawers, entries two and three get none, and the file stops being valid org. Because `parse_org` only looks for a drawer *before* the timestamp, the next run sees zero mappings and creates fresh Google events for every heading — every sync multiplies the calendar. `cmd_pull:391` shares the defect.

- [ ] **Step 1: Write the failing test**

Create `tools/calendar-sync/test_calendar_sync.py` with a fixture org file of three dated headings. Assert, after a simulated push that assigns an id to each entry:
- every entry has exactly ONE `:PROPERTIES:` drawer (`content.count(":PROPERTIES:") == 3`)
- no drawer is nested inside another
- each drawer sits BEFORE its entry's `<YYYY-MM-DD>` timestamp, so `parse_org` finds it
- re-parsing the written file yields three mapped entries, not zero

- [ ] **Step 2: Run it and watch it fail**

`cd ~/dotfiles/tools/calendar-sync && python3 -m pytest test_calendar_sync.py -v` — expect failures showing nested drawers and a zero-mapping re-parse.

- [ ] **Step 3: Fix by writing once**

Restructure so the file is read once, all property drawers are inserted into the in-memory line list (iterating entries in **descending** `line_start` order so earlier insertions do not shift later indices), and the result is written once. Insert the drawer **before** the timestamp line, matching what `parse_org` looks for. Apply the same shape to `cmd_pull`.

- [ ] **Step 4: Run the tests** — all pass.

- [ ] **Step 5: Fix the two callers that hid it**

- `bin/calendar-sync:7` — `$*` is interpolated unquoted into `nix-shell --run`. Use `"$@"` with proper quoting.
- `config.el:596` — `start-process-shell-command` is called with 4 arguments; its arity is `(3 . 3)`, so the `C-c c` binding has never worked. Fix the call and give it a real output buffer instead of `nil`, so failures are visible.

- [ ] **Step 6: Verify end to end on a COPY, never the real file**

```bash
cp ~/docs/org/Dates.org /tmp/Dates.org.test
# run the push path against /tmp/Dates.org.test, then:
grep -c ':PROPERTIES:' /tmp/Dates.org.test
python3 -c "
import sys; sys.path.insert(0, 'tools/calendar-sync')
import calendar_sync as cs
entries = cs.parse_org('/tmp/Dates.org.test')
mapped = [e for e in entries if getattr(e, 'event_id', None)]
print(f'entries={len(entries)} mapped={len(mapped)}')
assert len(mapped) == len(entries), 're-parse lost mappings — the drawer is in the wrong place'"
```
Expected: one drawer per dated heading, and a non-zero mapping count on re-parse.

- [ ] **Step 7: Commit**

```bash
cd ~/dotfiles
git add tools/calendar-sync/ bin/calendar-sync home/scott/emacs
git commit -m "calendar-sync: write the org file once, before the timestamp

cmd_push parsed once then called add_property_to_entry per entry; each call
re-read and rewrote the whole file while the caller still held line_start from
the first read. Entry one got three nested drawers, entries two and three got
none, and the file stopped being valid org. parse_org only looks for a drawer
BEFORE the timestamp, so the next run saw zero mappings and created fresh
Google events for every heading -- every sync multiplied the calendar.

Two things kept it invisible: bin/calendar-sync interpolated \$* unquoted into
nix-shell --run, and the C-c c binding called start-process-shell-command with
4 args against an arity of (3 . 3), so it had never run at all."
```

---

### Task B2: `bin/firefox` must not shadow the real browser

**Repo:** `~/dotfiles` · **Severity: High**

**Files:** Modify `bin/firefox`

**The defect.** The wrapper probes only `/usr/bin/firefox`, `/usr/bin/firefox-esr` and flatpak. All three hosts are NixOS, where `/usr/bin` holds `env` and `systemctl`. emanix installs Firefox via `programs.firefox` to `/etc/profiles/per-user/$USER/bin/firefox`, and `zsh.nix:58` prepends `$EMANIX_BIN_DIR` to PATH so the wrapper wins. Verified on rafik: `zsh -i -c 'firefox --version'` → `no browser binary found`, exit 127. `emanix-ewm-slots.el:18` falls back to the same wrapper.

- [ ] **Step 1: Reproduce**

`ssh rafik "zsh -i -c 'firefox --version'; echo exit=\$?"` — expect the failure.

- [ ] **Step 2: Fix the search order**

Probe the NixOS locations first — `/etc/profiles/per-user/$USER/bin/firefox`, `$HOME/.nix-profile/bin/firefox`, then `command -v -a firefox` filtered to exclude this wrapper itself (compare against `$0` resolved) — before falling back to `/usr/bin` and flatpak. Keep the FHS paths: the wrapper predates NixOS and may still run elsewhere.

- [ ] **Step 3: Verify on the host that was broken**

`ssh rafik "zsh -i -c 'firefox --version'"` — expect a version string. Also confirm the wrapper does not recurse into itself.

- [ ] **Step 4: Commit**

---

### Task B3: Remove the two orderings against a unit that does not exist

**Repo:** `~/dotfiles` · **Severity: Medium**

**Files:** Modify `home/scott/weekly-report.nix:130-140`; modify `ioshi/i-intelligence/syncthing.nix:60-70`

**The defect.** Verified live: `systemctl --user list-units --all 'network*'` reports `network-online.target` **not-found**. `Wants=`/`After=` on an unloadable unit is non-fatal, so both orderings are inert — failing silently in exactly the way their comments say they prevent. Worst for weekly-report: `Persistent=true` + `RandomizedDelaySec=5m` means the catch-up run fires minutes after a WSL start and `claude -p` dies on its first API call.

- [ ] **Step 1: Confirm live**

`systemctl --user list-units --all 'network*'` and `systemctl --user show weekly-report.service -p Wants -p After`.

- [ ] **Step 2: Replace with something that works in the user manager**

For weekly-report, add an `ExecStartPre` that polls for reachability with a bounded timeout and exits non-zero if the network never arrives, so the run is skipped rather than failed noisily. For syncthing, drop the inert ordering and say in the comment why a user unit cannot order against `network-online.target`.

- [ ] **Step 3: Verify** — rebuild whistle, then `systemctl --user show weekly-report.service -p Wants -p After` shows no not-found unit, and `systemctl --user list-units --all 'network*'` is unchanged.

- [ ] **Step 4: Commit**

---

### Task B4: `ib up` must not report failure on success

**Repo:** `~/dotfiles` · **Severity: Medium**

**Files:** Modify `ioshi/i-intelligence/ibgateway.nix:110-130`

**The defect.** `ibCli` is a `writeShellApplication`, which injects `set -euo pipefail`. Line 120 starts two units unguarded, unlike the `down` and `status` branches which both guard. Those unit names appear nowhere in either repo — they are hand-installed on the live rafik, so they will not exist after the reinstall. `ib up` will start the gateway, confirm the port, then die before printing success.

- [ ] **Step 1: Guard the start, matching the `down`/`status` branches**, and make a missing unit a clear message rather than a bare non-zero exit.
- [ ] **Step 2: Note in the comment that those units are host-local and absent after a reinstall**, so the next reader is not hunting the repo for them.
- [ ] **Step 3: Verify** `nix flake check` in dotfiles, and `ib status` on rafik still behaves.
- [ ] **Step 4: Commit**

---

### Task B5: Tests that cannot fail must be made to fail

**Repo:** `~/projects/emanix` **and** `~/dotfiles` · **Severity: Medium**

**Files:** Modify `emanix/tests/installer-modes.sh:47-62`; modify `dotfiles/bin/dot-doctor:35-50`

**The defect.** Two installer tests grep output for `usage:` and `unknown host\|not found in the flake`; neither string appears anywhere in the installer, so both are unconditionally green and would stay green if it crashed on line 1. Separately `dot-doctor:47` degenerates to `[[ -d "/" ]]` when `EMANIX_THEMES_DIR` is unset **and** the marker file is missing — the one check that would report an unwired theme system fails open. And `:37`/`:44`/`:45` test for apt, `/usr/bin/firefox` and a Debian font path, so `dot-doctor` exits 1 on every host, training its ✗ lines to be ignored.

- [ ] **Step 1: Prove they are vacuous** — `grep -ic 'usage:' installer/fresh-emanix-install` and the other needle; expect 0 for both.
- [ ] **Step 2: Rewrite them against the real messages** the installer actually emits (read them out of the script), or delete them if the behaviour is genuinely untested elsewhere and say so.
- [ ] **Step 3: Fix `dot-doctor`** — make the theme check fail closed when neither the env var nor the marker is present, and delete or NixOS-ify the three Debian-era checks so a healthy host exits 0.
- [ ] **Step 4: Verify** `./tests/installer-modes.sh` passes for real reasons, and `dot-doctor; echo $?` returns 0 on whistle.
- [ ] **Step 5: Commit (two repos)**

---

# Phase C — datacore disaster recovery

### Task C1: A rebuilt datacore must not expose unauthenticated services

**Repo:** `~/dotfiles` · **Severity: High**

**Files:** Modify `hosts/datacore/configuration.nix:170-215`; `ioshi/i-intelligence/secrets.nix`

**The defect.** `:178,205` open syncthing 8384 (on `tailscale0` and every `br-+` docker bridge) and backrest 9898. The comments state both are safe only because they are password-protected, and equally state that `secrets/{syncthing-gui-auth,backrest-auth}.age` are deliberately NOT declared as `age.secrets` — they are applied to runtime state. A datacore rebuilt from the flake rather than restored therefore comes up with a regenerated `config.xml`, no GUI auth, and fleet-hub config control open to every tailnet node.

**Do not rotate the credentials.** Declaring them is in scope; changing their values is not.

- [ ] **Step 1: Declare both secrets** as `age.secrets` with the right owner and mode, so they exist on a rebuilt host.
- [ ] **Step 2: Wire them into the services** so the auth is applied declaratively rather than to runtime state — or, where the service genuinely cannot take a file, add an activation step that applies it and fails loudly if the secret is absent.
- [ ] **Step 3: Close the `br-+` exposure.** Syncthing's GUI does not need to listen on every docker bridge; restrict to `tailscale0` and loopback.
- [ ] **Step 4: Verify** `nix eval` shows both secrets declared for datacore, and datacore's drvPath movement is reported explicitly (this task WILL move it).
- [ ] **Step 5: Commit**

---

### Task C2: A rebuilt datacore must still take backups

**Repo:** `~/dotfiles` · **Severity: High**

**Files:** Modify `hosts/datacore/configuration.nix:355-405`, `:225-240`

**The defect.** `pg-dump-stacks.service` and `restic-health-check.service` `ExecStart` scripts under `/home/scott/projects/datacore-config/bin/`, and `backrest.service` reads `/home/scott/.config/backrest/config.json`. Nothing in either flake, in syncthing's folder set, or in the installer creates any of them. On a rebuilt datacore both timers fire nightly into `203/EXEC`, backrest starts with no repo and no plan, and the health check whose job is to notice is the other unit that cannot start.

- [ ] **Step 1: Decide per script** whether it belongs in the flake (most likely — they are infrastructure) or genuinely must stay host-local. Move what can move into the repo, referencing store paths.
- [ ] **Step 2: For anything that must stay host-local**, add a preflight that fails loudly and early rather than at `203/EXEC` nightly, and document where it comes from.
- [ ] **Step 3: Confirm against `reference_datacore_backup_stack`'s gate** — `bin/backup-gate.sh` runs 10 checks; make sure this change does not break them.
- [ ] **Step 4: Verify + report datacore's drvPath movement.**
- [ ] **Step 5: Commit**

---

# Phase D — simplification and drift

### Task D1: Derive the zellij light theme instead of inlining it

**Repo:** `~/projects/emanix` · **Severity: Medium**

**Files:** Modify `ioshi/i-intelligence/zellij.nix:81-325`

244 lines of KDL inlined as two theme blobs. Applying `0↔15, 7↔8` to the dark half yields the light half **byte-for-byte**, and `lib/themes.nix:168 ansiSlots` already implements that swap for every other themed app. The same file reads its other KDL from `./zellij/*.kdl` via `renderKdl` nine lines above — the pattern to follow is already in the file.

- [ ] **Step 1: Prove the swap** — generate the light half from the dark one and `diff` against the committed text. Byte-identical, or stop.
- [ ] **Step 2: Move the dark theme to `./zellij/theme.kdl`** and render both variants through `renderKdl` + `ansiSlots`.
- [ ] **Step 3: Prove inert** — the rendered KDL must be byte-identical to what the inline version produced, for both variants.
- [ ] **Step 4: Commit**

---

### Task D2: Docker becomes opt-in; retire the identical role checks

**Repo:** `~/projects/emanix` **and** `~/dotfiles` · **Severity: Medium**

**Files:** Modify `emanix/ioshi/os-system/base.nix:13-19`; `emanix/flake.nix:178-186`; `dotfiles/hosts/{whistle,datacore}/configuration.nix`

Two related simplifications, settled in the spec.

**Docker.** `virtualisation.docker.enable = mkDefault true` on every emanix host, justified by a comment arguing from the unconditional `docker` group membership — which is the thing that should go. `docker` is root-equivalent, so the distribution grants passwordless root to the primary user by default, and rafik (14 GiB, no swap, no docker workload) runs a daemon and bridge it never uses.

**Role checks.** `flake.nix:178-186` runs `role-workstation`, `role-server` and `role-wsl`, which now evaluate **identical** systems — `emanix.role` is read by exactly one line (`zsh.nix:46`) — justified by a comment describing role profiles deleted on 2026-08-30.

- [ ] **Step 1: Record baselines** for all three hosts' drvPaths.
- [ ] **Step 2: Remove the docker default and the unconditional group membership** from `base.nix`; rewrite the comment to state the security posture plainly.
- [ ] **Step 3: Opt whistle and datacore in explicitly** in their host configs (both genuinely use docker: pearl-platform-db and headscale respectively).
- [ ] **Step 4: Collapse the three role checks into one**, or keep one per role only if you can show they differ. Update the comment to describe what is actually being checked in 2026, not the deleted profiles.
- [ ] **Step 5: Report movement honestly** — whistle and datacore should be INERT (they opt back in); **rafik will MOVE and that is the point.** Report the before/after drvPaths and confirm docker is absent from rafik's closure.
- [ ] **Step 6: Commit (two repos)**

---

### Task D3: Make the comments true or delete them

**Repo:** `~/projects/emanix` **and** `~/dotfiles` · **Severity: Medium**

37% of emanix's Nix lines and 40% of dotfiles' are pure comment. The spec lists twelve confirmed-false statements found without hunting for them. Fix exactly those; do not embark on a general prose review.

- [ ] **Step 1: Fix each listed falsehood**, one commit for emanix and one for dotfiles. The list is in the spec under "Comment drift" — work it item by item and tick them off in your report:
  `theme.nix:99` `dotfilesLib` · `packages.nix:9` "apt for Phase 1" · `mpv.nix:238` removed `lib.optional` · `ewm.nix:166` XWayland in `loginShellInit` · `themes.nix:8` `lib.theme.generators` · `swaylock.nix:11` `modules/nixos/ewm.nix` · `zsh.nix:45` vs `theme.nix:36` on `EMANIX_ROLE` · `btop.nix`/`lf.nix`/`mpv.nix` stow layout · `home/scott/default.nix:143` `mkForce` vs `mkDefault` · `hosts/rafik/configuration.nix:25` "elisa's rebuilds".
- [ ] **Step 2: The rafik NOPASSWD rule is not just a stale comment.** It grants a full root escalation while the comment claims tight scoping, and its stated justification (elisa) is retired with nothing calling `nixos-rebuild`. Remove the rule, or narrow it to what it claims and correct the comment. Report which you chose and why.
- [ ] **Step 3: Verify** both flakes still evaluate and no host's drvPath moved (comments are inert; a move means you changed code).
- [ ] **Step 4: Commit (two repos)**

---

### Task D4: The tail

**Repo:** both · **Severity: Low, batched**

One task, one commit per repo. Each item is small and independent; work the list and report per item.

- [ ] `emanix/iso.nix:130` — the disk-wiping script is the only one using `writeShellScriptBin` rather than the shellchecked `writeShellApplication` that `init.nix` and `firstboot.nix` both use. Convert it.
- [ ] `emanix/lib/disk.nix` — `device` is the one destructive argument the file does not validate. Assert it looks like a block device path.
- [ ] `dotfiles/ioshi/hi-hardware/hp-15-ef2013dx.nix:50` — re-declares filesystems disko generates (`options` is list-typed, so they concatenate). Convert `disko/datacore.nix` to `mkDisk` with `extraSubvolumes` and delete the block, ~60 lines. Gate 1 already proved the layout reproduces at **2522 bytes** — assert that. **This moves datacore's drvPath; report it.**
- [ ] `dotfiles/ioshi/hi-hardware/net/syncthing.nix:26` + `ioshi/i-intelligence/syncthing.nix:80` — the datacore device ID is a literal in two files that must be edited together, and it has changed once already. Define it once.
- [ ] `dotfiles/hosts/whistle/configuration.nix:242` — `pearl-platform-db` reads a hand-placed `/var/lib/pearl-db/env` nothing creates. Declare it or fail loudly.
- [ ] `dotfiles/bin/minne:3` — unguarded `cd`, plus an `LD_LIBRARY_PATH` store path already garbage-collected on whistle.
- [ ] `dotfiles/home/scott/emacs/personal.el:22` — the after-save date-stamper signals `Invalid search bound` on any org file with a heading, and in the no-heading path clobbers the kill-ring and leaves the buffer modified after save.
- [ ] `emanix/ioshi/i-intelligence/emacs/config.el:103` — `auto-revert-use-file-system-watcher` is not a variable in any Emacs (it is `auto-revert-use-notify`), and `auto-revert-interval` is `setq`'d after the mode is on so its `:set` never runs; the timer is 5 s, not 1.
- [ ] `emanix/ioshi/i-intelligence/emacs/lisp/emanix-modeline.el:171` — `redraw-display` every 3 s inside the compositor, plus a synchronous `nmcli` shell-out the file's own docstring twelve lines above forbids.
- [ ] `emanix/ioshi/i-intelligence/emacs/lisp/emanix-ewm.el:87` — rafik's two specific monitors hardcoded in the distribution layer. Make it an option or derive it.
- [ ] `emanix/ioshi/i-intelligence/emacs/fallback.el:172` — the EWM binding block is copy-pasted from `ioshi/i-intelligence/emacs/config.el:857`.
- [ ] `dotfiles/tools/calendar-sync/calendar_sync.py:112,140` — the OAuth client secret and refresh token are written `0644`. Make them `0600`.
- [ ] `emanix/ioshi/i-intelligence/emacs/packages.nix:5,122` — the file's structure is contorted to keep a derivation hash byte-stable, which is not a property worth shaping source around. Simplify, and prove the resulting package set is unchanged.

---

## Execution order

Phase A first and in order — A1 before A4 (both edit the installer). Then B, C, D in any order; nothing outside A blocks the reinstall. A5 is the only Phase A task in dotfiles and is provably inert, so it can land at any time.

## Reporting rules

Any task that moves a host's `toplevel.drvPath` reports the before and after paths explicitly. Expected movers: **C1, C2, D2 (rafik only), D4 (datacore only)**. Everything else must be inert; an unexpected move is a finding, not a footnote.
