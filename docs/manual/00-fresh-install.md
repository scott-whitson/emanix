# Fresh install — bare Debian to operational

The source of truth is **GitHub** (`scott-whitson/dotfiles`, private). A fresh box
can't SSH-clone a private repo before it has a key, so the first pull uses a
**read-only fine-grained PAT** over HTTPS. That's the only trick — everything else
is the normal profile install.

## One-time setup (do this once, keep it current)

1. **Create the read-only token** — GitHub → Settings → Developer settings →
   Fine-grained tokens → *Generate new*:
   - Repository access: **only** `scott-whitson/dotfiles` (add `datacore-config` if you
     want it too)
   - Permissions: **Contents → Read-only**
   - Expiry: 1 year (set a reminder to rotate)
   - Store the token in your password manager.
2. **Seed the USB** — put `ventoy/install.sh` and a `github-token` file (the token,
   one line) side by side on the Ventoy drive. `github-token` is gitignored, so it
   never lands in the repo.

## Fresh install

```bash
# 0. Debian installer: OS + user + network + hostname (set it to e.g. `zord`).

# 1. Run the bootstrap:
#    USB:  mount the drive, then
./install.sh
#    Web:  (no USB handy)
curl -fsSL https://scottwhitson.com/install | bash   # prompts for the token

#    → clones dotfiles from GitHub (HTTPS+token), switches origin to SSH,
#      runs install.sh with the auto-detected profile (hostname `zord` → desktop).

# 2. (authoring machines only) become a GitHub push peer:
dot-github-key
#    → generates an ed25519 key, you paste the pubkey at github.com/settings/keys,
#      verifies `ssh -T git@github.com`, repoints origin tracking to GitHub.
#    Read-only consumer boxes can skip this — the token already got them running.

# 3. Restore any host secrets from your password manager (see datacore-config
#    RECOVERY.md for the datacore-specific list).
```

## Notes

- **Profiles** auto-detect by hostname: `datacore` → server, WSL → wsl, else → desktop.
  Override with `./install.sh --profile <name>`.
- **Tailnet join** (Headscale) is a *separate* concern from dotfiles — use the
  `ventoy/bootstrap.sh` enrollment flow or `tailscale up` when you need datacore
  access. The dotfiles bootstrap no longer depends on it.
- **Token leak risk** is read-only access to config that contains no secrets.
  Rotate on expiry; revoke + regenerate if a USB is lost.
- The Ventoy USB is now the *offline* path; `scottwhitson.com/install` is the
  universal one. Both run the same script from the same GitHub source.
