# win-emacs — open Windows files in the WSL Emacs

Opens a file from the Windows side in the **already-running** WSL Emacs daemon,
rather than in Notepad/Notepad++. No second Emacs install.

    Explorer ──▶ open-in-emacs.vbs ──▶ wsl.exe -e open-in-emacs.sh ──▶ emacsclient
                       │                                                (daemon)
                       └──▶ focus-emacs.ps1  (raise the WSLg window)

## Install

    ./install.sh            # idempotent
    ./install.sh status     # what is registered right now
    ./install.sh uninstall  # remove everything it created

All writes are under `HKCU`. No admin, nothing machine-wide.

Source of truth is this directory; `install.sh` deploys a **copy** of the `.vbs`
to `%LOCALAPPDATA%\EmacsWSL\`. Re-run it after editing the `.vbs`. The copy is
deliberate — running the script off `\\wsl.localhost` would mean Explorer could
not read it while the distro is stopped, which is exactly when it needs to boot
it. (Same pattern as `../glazewm/focus-emacs.ps1`.)

## What works, and what needs one click

**Context-menu verb — works with no confirmation.** "Open in Emacs" on any file
type. Verified present in the real shell verb list and dispatching correctly.
On Windows 11 (build 26200 here) a legacy verb is demoted out of the top-level
context menu into **"Show more options"**, i.e. Shift+right-click. Reaching the
top-level menu requires a signed MSIX package implementing `IExplorerCommand` —
out of scope.

**Double-click — needs a one-time picker choice per extension.** Registering the
association is *not* sufficient on modern Windows. Verified: with `.md` mapped to
`EmacsWSL.File` in `HKCR` and **no** `UserChoice` present, `ShellExecute` still
raised the "How do you want to open this file?" picker. Windows wants the user to
confirm a handler, and writes `UserChoice` itself when they do.

So the association work buys you *"Emacs (WSL)" showing up in that picker*. Once
per extension:

> right-click > Open with > Choose another app > **Emacs (WSL)** >
> check "Always use this app"

After that it is permanent, because Windows wrote a proper `UserChoice`.

### UserChoice cannot be scripted — do not try

`HKCU\...\Explorer\FileExts\<ext>\UserChoice` holds a `Hash` value and carries a
Deny ACE; `reg delete` returns **"Access is denied."** It is an anti-hijack
measure. Do **not** work around it by rewriting the key's ACL: that is the exact
pattern EDR products flag as association hijacking, and this machine runs
corporate EDR.

### Extensions

Associated by `install.sh` (were unclaimed): `.md .org .json .yaml .yml .toml
.conf .el .nix .js .sql`

Associated but pending a picker click (were owned by a Notepad-class editor):
`.txt .log .ini`

**Deliberately not touched** — these belong to something that is not just a text
editor. Add to `CONTESTED_TAKE` in `install.sh` and re-run if you disagree:

| Ext | Owner | Why left alone |
|-----|-------|----------------|
| `.csv` | Excel | Excel is probably what you want for CSV |
| `.py` | VS Code | A real editor, your call |
| `.sh` | Git Bash | Double-click currently **runs** the script |
| `.ts` | media player | `.ts` is also an MPEG transport stream |

## Gotchas found the hard way

- **`wsl.exe -e` gives no shell and therefore no `PATH`.** Bash falls back to
  `/usr/local/bin:/usr/bin:/bin`, which on NixOS is nearly empty. `date` and `tr`
  both silently vanished; the missing `tr` made the frame count parse as `0`, so
  every open created a **new** frame instead of reusing the existing one.
  `open-in-emacs.sh` now sets `PATH` explicitly and uses only bash builtins.
- **No shell is also the point.** The Windows path arrives as one `argv` entry,
  so there is no shell-quoting layer to get wrong. Desktop paths contain a space
  *and* a comma (`OneDrive - Central Data Systems, Inc`), which is what breaks
  the usual `bash -c` recipes. Tested with a `space, comma` filename.
- **Frame reuse vs creation.** Handing a file to an existing frame needs no
  display env; *creating* one needs `WAYLAND_DISPLAY` + `XDG_RUNTIME_DIR`. Both
  branches are exercised.
- **`assoc` / `ftype` will lie to you.** They read only the `HKLM` half, so they
  report "File association not found" for a perfectly good per-user association.
  Check `reg query HKCR\<ext>` instead.
- **If a frame opens but paints nothing**, weston has `use_gfxredir=0`; only
  `wsl --shutdown` fixes it. The `ec` shell function warns about this; a
  Windows-launched open cannot, so it just looks like nothing happened.

## Debugging

    tail ~/.local/state/win-emacs.log

Every invocation logs one line: `reuse|create`, frame count, `emacsclient` exit
code, and the translated path. No log line at all means the chain never reached
WSL — suspect the `.vbs` or the registry command.
