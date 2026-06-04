# Datacore Bootstrap Plan

This is planning doc for next bootstrap layer.
It captures current state, phase split, and open decisions before backend work starts.

## Goal

Make blank Debian machine boot from Ventoy, enroll in datacore, join Headscale, fetch dotfiles, and finish bootstrap without manual password entry for long auth keys.

After bootstrap, **datacore and target machine must both be able to SSH into each other without password prompts**.

## Current state

### Client side

`ventoy/bootstrap.sh` already does:
- datacore bootstrap session create
- browser verification
- polling for approval
- Headscale join using short-lived token
- dotfiles fetch from datacore archive or git URL
- USB mirror fallback
- handoff to repo `./bootstrap.sh`
- completion callback

### Repo bootstrap

Root `bootstrap.sh` stays thin.
`bin/dot-bootstrap` still handles fresh-clone repo install, and `install.sh` runs numbered install steps.

### Backend design artifacts

- `docs/specs/datacore-bootstrap.openapi.yaml`
- `docs/specs/datacore-bootstrap-backend.md`

## Phase 1: enrollment bootstrap

Phase 1 is about getting machine alive and trusted.

### User flow

1. Boot Debian from Ventoy.
2. Run `ventoy/bootstrap.sh`.
3. Enter datacore URL, device name, and role.
4. Sign in on datacore.
5. Approve device.
6. Datacore returns short-lived bootstrap token.
7. Script joins Headscale.
8. Script fetches dotfiles.
9. Script runs repo `./bootstrap.sh`.
10. Script reports completion.

### Phase 1 SSH requirement

Bootstrap must also establish **reciprocal passwordless SSH** between:
- datacore → target machine
- target machine → datacore

This should be part of bootstrap, not a later manual step.

Preferred shape:
- machine generates SSH keypair during bootstrap
- client sends `machine_ssh_public_key` during enrollment
- datacore installs corresponding `authorized_keys` entry for its SSH user
- approved bootstrap response returns `ssh_trust_bundle` with `ssh_user`, `known_hosts`, and optional `ssh_config_snippet`
- bootstrap writes known_hosts / trust material so first SSH is non-interactive

If SSH CA / certs are available later, prefer that over raw keys. But phase 1 should work with plain key-based trust first.

### Phase 1 outputs

After bootstrap completes, machine should have:
- Headscale membership
- dotfiles installed
- working datacore SSH trust
- working SSH trust from datacore back to machine
- repo install finished cleanly

## Phase 2: sync management

Phase 2 extends bootstrap into ongoing sync.

Likely responsibilities:
- heartbeat
- drift check
- bundle request/download
- selective sync
- policy per role
- token rotation
- device disable / retire

Phase 2 should reuse the device record created in phase 1.

## Design rule

Do not block phase 1 on full sync engine.
Phase 1 only needs enrollment, trust, and bootstrap.
Phase 2 can build on top.

## Open questions

- SSH CA vs plain key install for first version
- whether datacore should store machine host key fingerprints at enrollment
- whether datacore should push an SSH config snippet in bootstrap bundle

## Working contract

If a future change touches bootstrap, it must keep this invariant:

> Fresh machine can enroll through datacore, join Headscale, fetch dotfiles, and establish passwordless SSH in both directions without manual long-secret typing.
