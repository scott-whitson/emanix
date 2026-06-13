# Ventoy bootstrap kit

Portable first-run helper for Debian machines.

## Default flow

This script is the blank-machine bootstrap path:

1. Start `bootstrap.sh`
2. Enter datacore URL, device name, and role if not passed on CLI
3. Open datacore verification URL in browser
4. Sign in, approve device, and receive short-lived bootstrap token
5. Install SSH trust bundle and join Headscale
6. Fetch dotfiles from datacore
7. Run repo `./bootstrap.sh`

## Layout

Copy this directory to Ventoy USB root, or keep it wherever you want and run `bootstrap.sh` from here.

Optional local mirror:

```text
ventoy/
├── bootstrap.sh
├── README.md
└── dotfiles/        # optional full repo mirror for offline or fallback use
```

## Use

```bash
./bootstrap.sh \
  --datacore-url https://datacore.example \
  --device-name fjord \
  --role desktop
```

If flags are omitted, script prompts for datacore URL, device name, and role.

## Datacore response

Enrollment session should return:
- `verification_url`
- `device_code`
- `bootstrap_token`
- `headscale_login_server`
- `ssh_trust_bundle`
- `dotfiles_archive_url` or `dotfiles_git_url`
- optional `device_id`
- optional `hostname`

Client also sends its `machine_ssh_public_key` during enrollment so datacore can install reciprocal SSH trust.

Archive fetch is tried first, then git URL, then local USB mirror.

## Legacy rescue mode

If datacore enrollment is unavailable, use manual Headscale fallback:

```bash
./bootstrap.sh \
  --legacy-login-server https://headscale.example \
  --legacy-headscale-authkey YOUR_AUTH_KEY
```

## Options

```bash
./bootstrap.sh --help
```

Useful flags:
- `--datacore-url URL` — datacore bootstrap portal base URL
- `--device-name NAME` — enrolled machine name
- `--role ROLE` — device profile/role
- `--target DIR` — install repo into alternate dir
- `--source DIR` — point at alternate local mirror
- `--no-browser` — suppress browser opener
- `--no-headscale` — skip Headscale join after approval
- `--legacy-login-server URL` / `--legacy-headscale-authkey KEY` — manual rescue path
