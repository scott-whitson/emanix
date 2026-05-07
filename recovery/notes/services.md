# Service re-enrollment after DR

Services whose machine identity doesn't restore from backup. Do these after Phase 4
of the runbook (user data restored, network up).

## Tailscale
Daemon state in `/var/lib/tailscale/tailscaled.state` is **not** backed up — Tailscale
treats each reinstall as a new peer identity.

Standard enrollment (opens browser for Google auth):

    sudo tailscale up

Headless/unattended (from a pre-generated auth key):

    sudo tailscale up --auth-key=tskey-auth-XXXX...

Auth keys live at https://login.tailscale.com/admin/settings/keys — generate a single-
use reusable key ahead of time and store it in Bitwarden for the DR scenario.

Verify peers are reachable:

    tailscale status
    tailscale ping datacore

## GitHub (for private dotfiles access if needed)
The restore flow sidesteps cloning the private dotfiles repo (they come out of the
home backup tarball). If you ever need to re-clone mid-recovery:

- Have a Personal Access Token ready in Bitwarden
- Clone via HTTPS: `git clone https://<PAT>@github.com/scott-whitson/dotfiles.git`
- Or restore the SSH key first (from the backup's `.ssh/id_ed25519`) and clone via SSH

## Google Drive (rclone)
First-time setup after reinstall:

    rclone config
    # → n (new remote) → name: gdrive → type: drive → OAuth device flow

This doesn't require any pre-existing creds beyond your Google account password +
2FA method. Recovery codes (paper in fire-proof box) are the fallback if 2FA is
unreachable.
