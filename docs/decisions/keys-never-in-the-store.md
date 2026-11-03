# Keys never go through the store

**Applies to** `installer/iso.nix` and `installer/fresh-emanix-install`.
**Decided** 2026-11-02, when the fleet path was deleted rather than hardened.

## Decision

No installer image carries key material, under any option. The distribution
stages the flake and nothing else. Keys for a fleet install come from a
removable medium the operator mounts, read at install time from a
`<host>-keys/` directory beside the repo (`resolve_keys`), or from a prompt. On
the default path the target's host key is minted on the target.

## Why deletion, and not a safer staging mechanism

An image is assembled from `/nix/store`. Every file in it is a store path, the
store is world readable by design (mode 0555, every local user can read every
path), and `environment.etc` entries are symlinks into it. So "the ISO carries
the host keys" states the same thing as "the host keys are published": there is
no option ordering, no permission bit and no `builtins.path` filter that stages
a private key into a NixOS image without a world-readable copy of it existing on
the build machine and in every image built from that closure.

The module did it anyway, through `builtins.path`, and a review of the
distribution's risk surface found it:

- `stagedKeys = builtins.path { path = cfg.keysDir; }` — the private host key
  halves, at `/nix/store/<hash>-emanix-keys`, mounted at `/etc/emanix/keys`.
- the same directory's `tailscale-preauthkey` — a *reusable* tailnet credential,
  which is the one thing worth stealing from a provisioning image, staged the
  same way at `/etc/emanix/tailscale-authkey`.

A keys-carrying ISO also had to be built with `--impure`, because the private
halves are gitignored and `builtins.path` was being used to read the real
working tree. That requirement was the tell: the build was reaching outside the
flake for state it had no safe way to carry.

## What replaced it

`resolve_keys` already had a second branch, and it is the one that survives:

    if [ -f "$(dirname "$REPO")/${FLAKE_HOST}-keys/${FLAKE_HOST}_host_ed25519" ]

Keys on a medium the operator controls, beside the repo being staged, or typed
at the prompt. An image built without them installs anyway — it mints the
target's host key — so the keyless path is not a degraded one.

The committed `keys/<host>_host_ed25519.pub` halves stay in the staged flake:
a `.pub` is the same string that is already in the repository, it is what
`resolve_keys` verifies a staged private half against, and a public key in the
store is not a secret.

## The guard

`checks/iso-no-keys.nix` evaluates the two files with their comment lines
dropped and fails if key material is routed through the image again, or if the
ISO stages more than one path. It runs at evaluation time because the PR gate
runs `nix flake check --no-build`: a guard that only fails when someone builds
an ISO is found months later, by whoever next builds one.

## Exit condition

None needed, and none possible. This is not a workaround for an upstream
limitation; it is the shape of a Nix store. If a future mechanism can put a file
into a NixOS image without it existing in `/nix/store`, this record is obsolete —
but nothing in the current design can.
