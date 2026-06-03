# Ventoy bootstrap kit

Portable first-run helper for Debian machines.

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

1. Boot Debian install.
2. Mount USB if needed.
3. Run:

```bash
./bootstrap.sh
```

## Headscale

Script prompts for:
- login server URL
- auth key

If you already have them, pass them non-interactively:

```bash
./bootstrap.sh \
  --login-server https://headscale.example \
  --authkey YOUR_AUTH_KEY
```

## Optional local mirror

If USB carries a cloned copy of repo at `ventoy/dotfiles/`, script uses that copy first; if clone from datacore fails, it falls back to the USB mirror.

To refresh local mirror, copy latest repo into that directory.

## Options

```bash
./bootstrap.sh --help
```

Useful flags:
- `--no-headscale` — skip Headscale join
- `--target DIR` — install repo into alternate dir
- `--remote URL` — use alternate dotfiles clone URL
- `--source DIR` — point at alternate local mirror
