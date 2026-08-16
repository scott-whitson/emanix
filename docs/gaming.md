# Gaming on eminix

Notes on running games on NixOS with EWM (Wayland + XWayland).

## Steam

`programs.steam.enable = true` is set in `ioshi/os-system/desktop.nix`.

### Steam Launch Wrapper

The Home Manager `steam` wrapper (`etc/profiles/per-user/scott/bin/steam`) starts XWayland if it's not already running, then delegates to the system FHS wrapper (`/run/current-system/sw/bin/steam`). This means launching `steam` from fuzzel or a terminal sets up X11 correctly.

### SteamLinuxRuntime Compatibility

**Problem:** `SteamLinuxRuntime_soldier` (Valve's container runtime) does not work on NixOS. Games launched from Steam's UI crash within seconds because the container environment can't find the expected FHS paths.

**Fix:** For each affected game:

1. Right-click game in Steam → **Properties**
2. Go to **Compatibility**
3. Check **"Force the use of a specific Steam Play compatibility tool"**
4. Select **"Steam Linux Runtime"** (the original scout version, NOT soldier)

### Factorio

- **Version:** 1.1.110 (beta)
- **Launch options:** `-windowed -g 1920x1200`
  - Fixes cursor offset in fullscreen on XWayland
  - `full-screen=false` is also set in `~/.factorio/config/config.ini`
- **Desktop entry:** `~/.local/share/applications/Factorio.desktop` launches via `steam steam://rungameid/427520`, which goes through the NixOS FHS wrapper — works without the compatibility tool fix
- **Mods:** SeaBlock modpack with Bob's/Angel's/SpaceMod

### SDL_VIDEODRIVER

The `programs.steam.package` override in `hosts/rafik/configuration.nix` forces `SDL_VIDEODRIVER=x11`. This is needed because Factorio 1.1 only supports X11 (not Wayland). XWayland handles the translation.

### Moonring — native LÖVE (primary), Proton focus fallback

Moonring is a LÖVE game shipped as a Windows build (`Moonring.exe`). Two ways to run:

- **Native (default):** `love Moonring.exe` with `SDL_VIDEODRIVER=wayland` — the game becomes a normal Wayland app, so keyboard "just works". `love` 11.5 is in `environment.systemPackages` (`ioshi/os-system/desktop.nix`). Saves live in `~/.local/share/love/Moonring/`. "Unable to load Steam" in the log is expected (no luasteam) and harmless.
- **Proton fallback (`moonring --proton`):** runs via Wine under X11 → XWayland. EWM shows all X11 windows as one merged `*ewm:Xwayland on :0*` surface and never moves X11-internal input focus to individual windows, so Wine gets no keys (mouse works, keyboard dead). The fallback re-asserts `xdotool windowfocus` on the game window.

`~/dotfiles/bin/moonring` (wired into `~/.local/share/applications/Moonring.desktop`) handles both: native first, `--proton` falls back. It is idempotent (flock + window check) so it never stacks a second instance.
