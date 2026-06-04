# Fjord → Zord reinstall runbook

Runbook for full wipe/reinstall/retest on current client box.

## Goal

Prove fresh machine can enroll through datacore, join Headscale, exchange SSH trust both ways, fetch dotfiles, and finish bootstrap.

After that, rename `fjord` to `zord`.

## Preconditions

Before wipe:
- Datacore bootstrap portal reachable
- `stacks/bootstrap-portal` deployed and healthy
- `ventoy/bootstrap.sh` current on USB
- `fjord` still boots today
- Datacore SSH trust path proven once
- `honcho-health` available on datacore if you want memory checks during/after

## Phase 1 — portal smoke

1. On datacore, ensure portal up:
   ```bash
   cd ~/projects/datacore-config
   bash bootstrap/23-bootstrap-portal.sh
   ```

2. Confirm portal health:
   ```bash
   curl -fsS http://127.0.0.1:8010/health
   ```

3. Smoke test contract:
   - create bootstrap session
   - approve in browser
   - confirm response returns:
     - `bootstrap_token`
     - `headscale_login_server`
     - `ssh_trust_bundle`
   - confirm completion callback works
   - confirm `authorized_keys.datacore` receives machine pubkey

## Phase 2 — Ventoy retest on fresh machine

1. Wipe/reinstall Debian on target box.
2. Boot Ventoy USB.
3. Run:
   ```bash
   ./ventoy/bootstrap.sh \
     --datacore-url https://datacore.example \
     --device-name fjord \
     --role desktop
   ```
4. Approve device in datacore browser page.
5. Verify after bootstrap:
   - Headscale connected
   - `ssh datacore` works from machine
   - datacore can SSH back without password
   - `dot-doctor` passes

## Phase 3 — rename cutover

Only after phase 2 succeeds:

1. Change hostname from `fjord` to `zord`.
2. Update datacore device name / portal device label if needed.
3. Verify:
   - `ssh zord` from datacore works
   - `ssh datacore` from zord works
   - bootstrap and trust still survive reboot

## Phase 4 — follow-up

After `zord` is stable:
- add phase 2 sync plane
- heartbeat
- bundle request/download
- drift detection
- policy updates

## Stop rules

Stop and fix before rename if any of these fail:
- portal contract mismatch
- SSH trust missing either direction
- Headscale join fails
- dotfiles bootstrap fails
- `dot-doctor` fails

## Short version

**No portal smoke, no wipe.**
**No SSH trust, no rename.**
**No clean Ventoy retest, no zord cutover.**
