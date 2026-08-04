# Standalone Home-Manager nodes (datacore, work-WSL)

Debian nodes run the eminix home layer (Emacs/meow/CLI) via standalone
Home-Manager from the same flake. See the spec:
`docs/superpowers/specs/2026-07-19-three-node-home-model-design.md`.

| Node | Flake attr | Profile | Notes |
| --- | --- | --- | --- |
| datacore | `scott@datacore` | server | syncthing/docker stay Debian-managed |
| ~~work-WSL~~ | ~~`scott@work`~~ | wsl | RETIRED 2026-08-04 with the Debian distro — replaced by the `weasel` nixosConfiguration (see `docs/ioshi/weasel.md`) |

## Bootstrap (once per node)

1. `curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes`
2. `echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf && sudo systemctl restart nix-daemon`
3. Move aside `~/.zshrc`, `~/.gitconfig`, `~/.emacs.d` (activation lists any
   further collisions — move each to `<name>.pre-hm`); keep the machine's git
   identity in `~/.gitconfig.local` before removing `~/.gitconfig`
4. `cd ~/dotfiles && nix build '.#homeConfigurations."scott@<node>".activationPackage' && ./result/activate`

## Day 2

- `home-manager switch --flake ~/dotfiles#scott@<node>` after pulling repo changes
- Emacs runs as a user daemon: `systemctl --user {status,restart} emacs`
- elisa: `ELISA_VEC0_PATH` is set, but chat needs an Ollama — deferred; not
  available on these nodes yet
- pi auth: `~/.pi/agent/auth.json` is hand-managed on standalone nodes (the
  agenix symlink only exists on NixOS hosts) — copy/create it manually or pi
  won't authenticate

## Emacs access on the work-WSL (verified 2026-07-20)

WSLg is present (`WAYLAND_DISPLAY=wayland-0`, `/mnt/wslg` populated) and the
GUI path works — with three gotchas found in live testing:

- **Use `ec` (or `emacsclient -c -d "$WAYLAND_DISPLAY"`), not bare
  `emacsclient -c`.** WSLg sets both `$DISPLAY` and `$WAYLAND_DISPLAY`, and
  emacsclient prefers `$DISPLAY` — pgtk Emacs then opens an X11 frame, which
  is unsupported (a "pure-GTK under X" warning on every launch, sporadic
  crash risk, keyboard quirks). The `ec` shell function (zsh.nix) passes the
  Wayland display explicitly; verified frames report `GdkWaylandDisplay`.
- **GlazeWM must not manage the WSLg EMACS window** — the pgtk frame is
  RDP-remoted through `msrdc.exe` and doesn't honor tiling resizes (window
  stays small/unusable). Other WSLg windows (ghostty, ...) tile FINE and
  want managing. Since 2026-07-23 the GlazeWM config
  (`C:\Users\swhitson.CENTRALDATA\.glzr\glazewm\config.yaml`) ignores
  `window_process: msrdc` + `window_title` regex `(?i)emacs` — and init.el
  pins `frame-title-format` to always contain "emacs" (the default
  collapses to bare `%b` with multiple frames, which would silently
  re-enroll Emacs into tiling).
- **Known limitation:** the WSLg window would not move to the external
  monitors in testing (stuck on the laptop display). Unresolved; revisit
  after the Wayland-native + GlazeWM-ignore changes.

Fallback that always works: `et` (`emacsclient -t`) in the terminal.

On datacore (headless), use `et` over ssh; `ec` falls back to a plain
`emacsclient -c` when no Wayland display exists.
