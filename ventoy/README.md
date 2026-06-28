# Ventoy bootstrap kit

Portable first-run installer for any Debian machine (datacore, zord, WSL, bare metal).

## What this does

1. Reads a GitHub PAT from `.pat` on this USB
2. Prompts for profile (desktop / server / WSL)
3. Clones dotfiles from GitHub
4. Runs `./install.sh --profile <name>`

That's it. No datacore enrollment, no Headscale, no SSH trust bundles — those
live in `datacore-config` on the server. This USB is portable and
machine-agnostic.

## Setup

### 1. Create `.pat` on the USB

```bash
# On any machine, after plugging in the Ventoy USB:
echo 'ghp_YourPersonalAccessToken' > /path/to/ventoy/.pat
chmod 600 /path/to/ventoy/.pat
```

Get a PAT at <https://github.com/settings/tokens> — "repo" scope for private
repos, no scopes needed for public.

### 2. Boot the target machine from Ventoy

After the live environment is up:

```bash
cd /path/to/ventoy
./bootstrap.sh
```

Or non-interactive:

```bash
./bootstrap.sh --profile server
```

## Profiles

| Profile  | Use case                    | Installs                                            |
|----------|-----------------------------|-----------------------------------------------------|
| desktop  | Workstation with Hyprland   | Full stack: Hyprland, Waybar, desktop services      |
| server   | Headless Debian server      | Core, tools, services — no GUI                      |
| wsl      | Debian under Windows        | Core, tools, services — no GUI, no Hyprland         |

## Layout

```text
ventoy/
├── bootstrap.sh          # installer (run this)
├── .pat.example          # instructions for creating .pat
├── .pat                  # your GitHub PAT (chmod 600, gitignored)
└── README.md             # this file
```

## After install

```bash
# Verify everything landed correctly:
~/dotfiles/bin/dot-doctor

# Pull latest + restow (normal machines):
~/dotfiles/bin/dot-sync
```

## What's NOT on this USB

- **Server config** (Headscale, SSH trust, Docker stacks) → `datacore-config` repo
- **dotfiles mirror** — cloned fresh from GitHub every time
- **Machine-specific secrets** — managed per-machine after install
