# Zord reinstall runbook

Runbook for the full wipe, reinstall, and retest cycle on the current client machine named `zord`.

## Goal

Prove that a fresh Debian machine can:

- enroll through datacore
- join Headscale
- establish passwordless SSH in both directions
- fetch dotfiles
- complete bootstrap successfully

During reinstall, name machine `zord` so hostname matches from first boot.

## Path convention for the reinstall

- datacore remains the canonical source tree host (`~/projects/...`)
- a temporary lab tree is optional on developer machines (`~/lab/...`)
- zord should only keep installed products and runtime state; it does not need project checkouts for things like fragpaper unless you are explicitly debugging them

## Preconditions

Before wiping anything, make sure:

- the datacore bootstrap portal is reachable
- `stacks/bootstrap-portal` is deployed and healthy
- the current `ventoy/bootstrap.sh` is on the USB
- `fjord` still boots normally
- the datacore SSH trust path has been proven at least once
- `honcho-health` is available on datacore if you want memory checks during or after the process

## Phase 1: portal smoke test

1. On datacore, make sure the portal is up:

   ```bash
   cd ~/projects/datacore-config
   bash bootstrap/23-bootstrap-portal.sh
   ```

2. Confirm the portal health endpoint works:

   ```bash
   curl -fsS http://127.0.0.1:8010/health
   ```

3. Smoke-test the bootstrap contract:
   - create a bootstrap session
   - approve it in the browser
   - confirm the response includes:
     - `bootstrap_token`
     - `headscale_login_server`
     - `ssh_trust_bundle`
   - confirm the completion callback works
   - confirm `authorized_keys.datacore` receives the machine public key

## Phase 2: Ventoy retest on fresh machine

1. Wipe and reinstall Debian on the target machine.

2. Boot into the newly installed Debian system, then mount the Ventoy USB if needed.

3. Run `ventoy/bootstrap.sh` from the USB mount or copied local path:

   ```bash
   ./ventoy/bootstrap.sh \
     --datacore-url https://datacore.example \
     --device-name zord \
     --role desktop
   ```

4. Approve the device in the datacore browser page.

5. After bootstrap completes, verify:
   - Headscale is connected
   - `ssh datacore` works from the machine
   - datacore can SSH back without a password
   - `dot-doctor` passes

## Phase 3: verify `zord` install

During the reinstall, set hostname to `zord` from the start.

After the Ventoy retest succeeds:

1. Verify the installed system already reports hostname `zord`.
2. Update datacore device name or portal label if needed.
3. Verify:
   - `ssh zord` works from datacore
   - `ssh datacore` works from `zord`
   - the bootstrap and SSH trust survive reboot

## Phase 4: follow-up

Once `zord` is stable, move on to phase 2 sync work:

- heartbeat
- bundle request/download
- drift detection
- policy updates
- selective sync

## Stop rules

Stop and fix the issue before verifying `zord` if any of these fail:

- portal contract mismatch
- SSH trust missing in either direction
- Headscale join failure
- dotfiles bootstrap failure
- `dot-doctor` failure

## Short version

- No portal smoke, no wipe
- No SSH trust, no rename
- No clean Ventoy retest, no `zord` verification
