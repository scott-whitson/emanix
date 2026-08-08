# Historical chapters

Superseded guides, kept because they record how the system used to work — not
how it works now. Nothing here is accurate for the current setup.

| File | What it was | Superseded by |
|---|---|---|
| `debian-install.md` | The Debian 13 bootstrap: `install.sh` + numbered `install/*.sh` steps, stow, apt | The flake. `installer/fresh-eminix-install`, then `nixos-rebuild switch --flake .#<host>` |
| `nixos-install-pre-disko.md` | Manual `parted` partitioning on zord-old, pre-disko and pre-ioshi | [`docs/ioshi/eminix-install.md`](../../ioshi/eminix-install.md) |

Moved out of the numbered sequence on 2026-08-08 so chapters 01–06 describe only
the live system. The remaining chapters were renumbered to close the gap.
