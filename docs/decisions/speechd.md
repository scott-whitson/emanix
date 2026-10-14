# The distribution does not ship text-to-speech

**Decided** 2026-08-18. **Applies to** `emanix.nix`, `config.services.speechd`.

## Decision

`services.speechd.enable = lib.mkOverride 500 false`. No emanix host carries a
screen reader, and a host can still turn one on with a plain definition.

## Why

`nixos/modules/services/misc/graphical-desktop.nix` enables `services.speechd`
for anything that declares itself a graphical desktop, which every EWM host now
does. The chain is speech-dispatcher -> espeak-ng -> mbrola -> mbrola-voices,
and **the voice data alone is 645 MiB**.

Measured on datacore with `nix path-info --closure-size -h` on both toplevels:

| State | Closure |
| --- | --- |
| before importing `modules/ewm.nix` | 6.2 GiB |
| with `ewm.nix` imported | 7.4 GiB |
| with this override | 6.7 GiB |

More than half the apparent cost of "EWM" was text-to-speech that nothing in
this distribution ever calls. EWM itself is 16.5 MiB.

## Why mkOverride 500, and not the obvious strengths

- `mkDefault` **ties** with that module's own `mkDefault true` and fails with
  "conflicting definition values".
- `mkForce` would stop a host disagreeing without `mkForce` of its own.
- `mkOverride 500` outranks that module's `1000` while still losing to a plain
  definition (`100`) in a host's config, so a machine that genuinely needs a
  screen reader writes `services.speechd.enable = true;` and wins.

## Rejected

Stating this per-role. It is true of every emanix box, and `profiles/roles/`
no longer exists.
