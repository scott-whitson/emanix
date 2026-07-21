# Work-content sync (Phase 3)

Work docs and projects replicate from the work-WSL through datacore (the
versioned hub) to eminix. Spec:
`docs/superpowers/specs/2026-07-19-three-node-home-model-design.md`.

| Share | WSL path | datacore/eminix path | Devices |
| --- | --- | --- | --- |
| `work-projects` | `~/projects` (all of it) | `~/projects/work` | WSL ↔ datacore ↔ eminix |
| `work-docs` | `~/docs/org/work` | `~/docs/org/work` | WSL ↔ datacore (eminix gets it via `docs`) |

- **Path asymmetry is deliberate:** the WSL's whole `~/projects` IS work;
  personal nodes keep it namespaced under `work/`.
- **`~/clients` never syncs** — it lives outside `~/projects` on the WSL.
- Single-writer discipline: the WSL is the writing machine for work repos;
  treat datacore/eminix copies as read-mostly. Recovery = datacore's
  `.stversions` (staggered, 30 days).
- Build junk (`node_modules`, `.venv`, …) is `.stignore`d on every node —
  no trailing slashes in those patterns, and `.git` is NOT ignored.
- The WSL connects via syncthing relays (userspace tailscale can't route
  the tailnet); small-change latency of 30s–3min is normal.
- The old Obsidian vault was folded into `~/docs/org/work` and the OneDrive
  copy renamed `docs-retired-20260720` (2026-07-20); Emacs/org owns work
  notes now (converted to org-roam `.org` on 2026-07-21 — see
  `docs/superpowers/specs/2026-07-21-work-vault-md-to-org-design.md`).
- WSL syncthing is HM-managed (`ioshi/i-intelligence/syncthing.nix`);
  datacore is Debian-managed (REST); eminix is the NixOS module.
