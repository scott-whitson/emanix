# Host runbooks

Operational guides: how to install, cut over and run a specific machine. For how
the system *works* rather than how to operate it, see [`../manual/`](../manual/).

The directory is named after the `ioshi/` module tree the flake is organised
around (`i-intelligence` / `os-system` / `hi-hardware`) — not because these docs
are about that tree.

| Doc | Host | What it covers |
| --- | --- | --- |
| [`eminix-install.md`](eminix-install.md) | `rafik` | Bare-metal install: Ventoy + disko + `nixos-install`, host-key injection, first boot. The template for any new workstation |
| [`whistle.md`](whistle.md) | `whistle` | NixOS-WSL bring-up, the agenix recipient flow, tailscale/syncthing join rituals, and the WSL gotchas that cost real time |
| [`work-sync.md`](work-sync.md) | all | Work-content sync topology — which folders replicate where, and the deliberate path asymmetry |
| [`standalone-hm.md`](standalone-hm.md) | — | **Retired.** Standalone Home Manager on a foreign distro. Kept for the still-accurate WSLg/GlazeWM notes |

Finished and retired runbooks are in [`history/`](history/).

## Not yet written

The **datacore NixOS cutover**. datacore is still Debian 13 and its
`nixosConfigurations` entry is a target, not a running system — the plan is to
build it on the HP that `zord-old` used to run. Design:
[`../superpowers/specs/2026-08-05-datacore-nixos-design.md`](../superpowers/specs/2026-08-05-datacore-nixos-design.md).

Two things to carry into that work, both learned the hard way:

- `home-manager.backupFileExtension` is set, so Debian-era files at HM-owned
  paths get renamed rather than aborting the whole switch.
- `~/.pi/agent` is a Syncthing folder. Deleting anything inside it propagates to
  peers — stop syncthing in the right scope first (it is a *user* service on
  datacore, a system service elsewhere) and verify the stop before deleting.
