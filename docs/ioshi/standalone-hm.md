**RETIRED 2026-08-05.** The last standalone-HM node (Debian datacore) is
migrating to NixOS (`docs/superpowers/specs/2026-08-05-datacore-nixos-design.md`);
the flake's `homeConfigurations` output is deleted, so the build commands
below no longer work. Kept for the still-accurate WSLg/GlazeWM notes.

# Standalone Home-Manager nodes (datacore, work-WSL)

Debian nodes run the eminix home layer (Emacs/meow/CLI) via standalone
Home-Manager from the same flake. See the spec:
`docs/superpowers/specs/2026-07-19-three-node-home-model-design.md`.

| Node | Flake attr | Profile | Notes |
| --- | --- | --- | --- |
| datacore | `scott@datacore` | server | syncthing/docker stay Debian-managed |
| ~~work-WSL~~ | ~~`scott@work`~~ | wsl | RETIRED 2026-08-04 with the Debian distro — replaced by the `whistle` nixosConfiguration, named `weasel` at the time (see `docs/ioshi/whistle.md`) |

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
  stays small/unusable). The GlazeWM config ignores `window_process: msrdc`
  + `window_title` regex `(?i)emacs` — and init.el pins
  `frame-title-format` to always contain "emacs" (the default collapses to
  bare `%b` with multiple frames, which would silently re-enroll Emacs
  into tiling). Settled 2026-08-05 after trying set-floating: Scott wants
  GlazeWM fully hands-off.
- **The GlazeWM config is tracked in the repo** at `tools/glazewm/`
  (`config.yaml` + dormant `focus-emacs.vbs`/`.ps1` force-focus scripts,
  currently unbound). The repo is authoritative: edit there, and
  `dot-sync` (via `bin/dot-glazewm-push`) overwrites the Windows copy,
  printing any discarded drift. Hand-edits on the Windows side don't
  survive a sync. Design: `docs/superpowers/specs/2026-08-05-glazewm-
  sync-design.md`. Two hard-won config facts: the `lwin+shift+arrow` move
  bindings stay UNBOUND (hjkl only — GlazeWM registers bindings globally
  and would swallow Windows' native move-to-monitor even for ignored
  windows), and window-rule edits need a GlazeWM RESTART, not reload
  (reload never re-evaluates windows it has already seen).
- **RESOLVED (2026-08-05): "window won't move to external monitors" was
  never GlazeWM.** WSLg's guest compositor gets the monitor layout at
  session start; an undock/redock can wedge it on a single output, after
  which interactive drags clamp at that monitor's edge (programmatic
  SetWindowPos still crosses fine — that asymmetry is the tell). Fix:
  `wsl --terminate weasel` from PowerShell **while docked**, reopen.
  Diagnose: `emacsclient --eval '(display-monitor-attributes-list)'` — a
  single `"rdp"` geometry means wedged; or grep `Head detaching` /
  `MonitorCount` in `/mnt/wslg/weston.log`. Also: native
  `Win+Shift+arrows` never move a focused WSLg window (msrdc forwards
  Win-combos into the guest) — mouse drag is the way.

Fallback that always works: `et` (`emacsclient -t`) in the terminal.

On datacore (headless), use `et` over ssh; `ec` falls back to a plain
`emacsclient -c` when no Wayland display exists.
