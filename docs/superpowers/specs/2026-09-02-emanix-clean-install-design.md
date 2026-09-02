# Clean install: two-mode installer, `emanix-init`, and the welcome buffer

**Status:** design, approved in conversation 2026-09-02. Not implemented.

## The goal, in the user's words

> "how to improve the installation and setup (hostname, internet, install,
> emacs (and an intro welcome letter), that's what I envision for a very clean
> install)"

## Where things actually stand

The installer is in better shape than its documentation was. `installer/fresh-emanix-install`
(250 lines) already has a real preflight — UEFI, network, Secure Boot, target-disk
auto-detection, and a host-key fingerprint check that fails *before* wiping anything.
`installer/iso.nix` already builds a live ISO that bakes a flake at `/etc/emanix/flake`
and keys at `/etc/emanix/keys`, and already asserts at build time when a keys directory
holds only `.pub` halves.

The site's installation page has been corrected separately (emanix.net, 2026-09-02) and
is no longer part of this work.

**What is missing is a mode.** `fresh-emanix-install` requires a `<host>` that already
exists in the staged flake, with a committed disko layout, a staged host key, and secrets
encrypted to it. It therefore cannot install a machine it has never heard of — which is
every machine belonging to anyone who is not the author.

## Decisions taken

| Question | Decision |
| --- | --- |
| Audience | **Both**, one flow: the pre-staged path for the existing fleet, and a generate-a-host path for everyone else |
| What a stranger ends up with | **Their own flake**, from a new `templates` output |
| Welcome letter | An **Emacs buffer** (`*emanix-welcome*`), not a terminal print |
| Structure | **Two-stage**: the installer does the minimum to boot; `emanix-init` makes the result habitable |
| `emanix-init` location | **In the distribution** — it exists to help people get an emanix install set up |

## Section 1 — the seam

### New in emanix

| Piece | What it is |
| --- | --- |
| `templates/default/` + a `templates` flake output | The flake skeleton a generated host gets, **including a parameterized `disko.nix`** (device, LUKS on/off, filesystem, swap size). Makes `nix flake init -t github:scott-whitson/emanix` real; no such output exists today. |
| `bin/emanix-init` | Stage two. Moves the generated config into `~/flake`, `git init`s it, adds `keys/`, a README, an agenix skeleton, and runs `nix flake check` to prove it evaluates. |
| `emacs/lisp/emanix-welcome.el` | The welcome buffer, plus `M-x emanix-welcome` to reopen it. |
| `checks/welcome-keys.nix` | Drift guard — see Section 3. |

**The disk layout goes in the template, not in `lib/`.** emanix ships no disko layouts
today, on purpose: a disk layout is a fact about a machine, and the two that exist
(`rafik`, `datacore`) live in the *consuming* repo. Putting a `lib/disko/generic.nix` in
the distribution would breach that boundary for no gain. Shipping it inside
`templates/default/` puts it in the generated repo, where the stranger owns their own disk
facts exactly as dotfiles owns ours. `whistle` has no layout at all, which is the same
reason WSL hosts are out of scope below.

### Unchanged, deliberately

- **`installer/iso.nix`.** `keysDir = null` already yields a keyless ISO, which is exactly
  what a stranger boots. No change needed.
- **`ioshi/os-system/firstboot.nix`.** Stays a pure seam. The welcome buffer is *not*
  firstboot content: firstboot means "join my infrastructure", which belongs to the
  consumer and must stay there.
- **`dotfiles`** gets nothing. The pre-staged path is the mode that already works.

### The distro/consumer boundary, restated

The welcome buffer must **compute** two things at runtime, never at build time:

1. **Does a config repo exist on this machine?** False at first boot on a stranger's
   machine and true after `emanix-init`, so it cannot be a build-time constant.
2. **Where is it?** Read `emanix.src.dotfilesPath` when the consumer sets it, else the
   generated `~/flake`, else show nothing rather than a wrong path.

Hardcoding `~/dotfiles` into distribution elisp is the exact defect that left
`emanix-elisa.el` pointing at `/home/emanix/dotfiles` — a path on no machine — for six
weeks. `checks/arc-glue.nix` exists because of it. Do not reintroduce it.

### Known cost

`emanix-init` writing a flake means **the distribution generates Nix code**, which it has
never done. A template that drifts from the distro's real option names produces a flake
that does not evaluate, and the person hitting that is a stranger with no context. This is
why `checks/` must build the template's host on every CI run.

## Section 2 — the installer's two modes

### A correction to the two-stage idea

The first sketch had the installer "stop at a booting system" with `emanix-init`
generating the flake. **That is not possible.** `nixos-install --flake <ref>#<host>`
requires the host to already exist in some flake, so an unknown host means the installer
*must* write a flake before it can install anything. The split is therefore:

- **The installer writes the minimum to boot** — hostname, disko layout, `emanix` import.
  ~30 lines of Nix from the template, into `/mnt/etc/nixos`. Small and mechanical.
- **`emanix-init` makes it habitable** — moves it to `~/flake`, `git init`, `keys/`,
  README, optional agenix skeleton, and `nix flake check`.

The virtue that made this shape worth choosing survives: the *destructive, unrepeatable*
step stays minimal, and everything else happens in a warm environment where retry is free.
Both consumers read the same `templates/default/`, so they cannot drift from each other.

### Mode detection

Ask the flake rather than keeping a list:

```bash
nix eval /etc/emanix/flake#nixosConfigurations --apply builtins.attrNames
```

- `fresh-emanix-install <host>` where `<host>` is in that list → **today's path, unchanged.**
- No argument, or a name not in the list → interactive mode.

This inverts current behaviour, where a missing host argument is a hard `die`.

### Interactive mode

| Step | Change |
| --- | --- |
| Hostname | Prompt, validate against RFC 1123 (lowercase alphanumeric and hyphen, ≤63 chars). New. |
| Network | Today the preflight only *pings* and fails closed. Add an `nmtui`/`iwctl` handoff when there is no route. `iso.nix` already sets `wifi.backend = "iwd"` so both work — this is UX, not capability. |
| Disk | Existing auto-detection already works. Add prompts for the template layout's knobs: LUKS, filesystem, swap. |
| Host key | Generate a fresh ed25519 pair on the target instead of requiring a staged one, and **skip the agenix fingerprint preflight** — there are no secrets to decrypt. |
| Install | `nixos-install --flake /mnt/etc/nixos#<hostname>` |

### CI guard

The known-host path is the one the fleet depends on and the one most likely to be broken
by a refactor of the other. Add a check asserting
`fresh-emanix-install <fixture-host> --check-only` still passes, so mode detection cannot
silently swallow it.

## Section 3 — the welcome buffer

`emacs/lisp/emanix-welcome.el`, following the `lisp/` module convention and written under
`fallback.el`'s discipline: **no package requires, no network.** It runs at startup, and
must never be the thing that breaks a first boot.

- `M-x emanix-welcome` reopens it; `emanix-welcome-mode` derives from `special-mode`
- Shown automatically on first start unless dismissed
- Dismissal state in `$XDG_STATE_HOME/emanix/welcome-dismissed`; `q` buries for this
  session, `n` writes the file
- `i` appears **only** when no config repo is found, and calls `emanix-init`

Content is **~10 curated lines**, not the manual: what the handful of essential keys are,
where the config lives, and a pointer to emanix.net.

Naming note: `emanix-welcome` is safe, but the general hazard is real — `arc-mode` is a
built-in Emacs library and must never be shadowed. Check any new name against built-ins.

### Rejected: generating the keybinding table

An earlier suggestion in this conversation was to generate both the welcome buffer and
`emanix.net/docs/keybindings.html` from one shared table, so they could not drift. The
measurements refute it:

| | |
| --- | --- |
| Keybindings page | 328 lines, **76 table rows**, 25 headings |
| Distinct `s-` bindings in emanix's elisp | **7** |
| Page rows mentioning `s-` | **23** |

Two-thirds of the documented super-key surface is **not in emanix at all** — `s-1…s-9`,
the arrows, `s-Tab`, `s-f`, `s-d`, `s-l`, `s-c`/`s-v` come from EWM upstream's own keymap
in the `ewm` flake input. Documentation cannot be generated from source in another repo.

Three further reasons:

1. **`fallback.el` is a deliberate second definition site**, re-binding the same keys so a
   broken `config.el` still leaves a usable desktop. A generator must pick one and would
   then misdescribe the other.
2. **Rows aggregate.** `s-1 … s-9` is one row covering nine bindings; `s-←/→/↑/↓` is one
   row covering four. 76 rows do not map onto the 54 binding forms in the elisp (37 `global-set-key`, 17 `define-key`).
3. **The Action column explains.** "keyed by number — `s-3` never conjures 1 and 2" is the
   sentence that makes the row worth reading, and no generator writes it.

### Instead: `checks/welcome-keys.nix`

Mirroring how `checks/arc-glue.nix` guards the arc glue:

- every key string the welcome buffer displays must appear in `keybindings.org`
- every command it names must exist in the elisp
- fails the build, and **proven to fail**, not assumed

This catches the failure that actually happened — the live site advertising `elisa` for
weeks after arc replaced it — at a fraction of the cost of generation.

## Non-goals

- Rewriting the pre-staged install path. It works; interactive mode is additive.
- Secrets for a generated host. A stranger gets **no** agenix secrets; the existing ones
  are encrypted to recipients they do not hold. `emanix-init` may lay down a skeleton, but
  provisioning secrets is out of scope.
- Multi-disk, RAID, or ZFS layouts in the template. One sane parameterized layout.
- Any change to `dotfiles`.

## Risks and open questions

1. **The template's `disko.nix` is the real unknown.** "A sane layout for an arbitrary
   disk" hides decisions — LUKS, subvolumes, swap sizing — and the two hand-written
   layouts in the consuming repo answered them differently from each other (`rafik` has
   LUKS, `datacore` does not). It should be built and tested against a VM before the
   installer depends on it.
2. **The first generation is not reproducible from the stranger's repo**, because the repo
   does not exist until `emanix-init` runs. Judged acceptable — stock NixOS has the same
   property — but it is a real cost.
3. **Template drift** is the failure mode most likely to reach a stranger. Hence the CI
   requirement above.
4. **`nix flake init -t` writes into a directory, not `/mnt`.** Whether the installer
   invokes the template through `nix flake init` or copies `templates/default/` directly is
   unresolved; the second is likely simpler inside a live ISO.

## Verification plan

- The template's `disko.nix` proven in a VM, each knob combination, before the installer uses it.
- `nix flake check` in emanix must build the template's example host.
- `fresh-emanix-install <fixture> --check-only` asserted green in `checks/`.
- The welcome buffer's key claims asserted against `keybindings.org` by `checks/welcome-keys.nix`,
  and that check demonstrated failing on a deliberately wrong key before being trusted.
- A full interactive install into a VM, from a keyless ISO, ending at a booted system with
  `*emanix-welcome*` shown and `emanix-init` producing a flake that evaluates.
