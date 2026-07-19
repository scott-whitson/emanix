# Chapter 07 — Nix Roadmap

> **Status:** Planning phase. Debian 13 (trixie) on zord.
> **Target:** Standalone Nix + Home Manager on Debian (Phase 1) → Full NixOS (Phase 2).
> **Go:** Build the flake alongside the existing bash/stow system. Deploy Nix first, drop Debian when the config covers everything.

This chapter is the migration plan. It exists so you can review the full scope at work before changing anything on zord.

---

## Why

The dotfiles project already turns OS install into a declarative, reproducible, profile-driven process — but it's built on bash + stow + apt. NixOS (and Home Manager) do the same thing at the *language level*, with real dependency management, rollbacks, and a community package set instead of hand-written install scripts.

The payoff:

| Current (bash + stow) | NixOS + HM |
| --- | --- |
| 11 numbered install scripts manually maintained | `environment.systemPackages` + `home.packages` from nixpkgs |
| Theme system: per-app per-theme files + symlink switcher | Theme system: Nix function generates configs from a palette |
| `stow` for dotfiles, but conflicts with HM writing the same paths | HM owns `~/.config/*` declaratively |
| Profile selection via shell sourcing | Flake outputs: `nixosConfigurations.zord`, `.datacore` |
| `apt update` drift over time | Single `nixos-rebuild switch` for total determinism |
| No native rollback for user config | `home-manager generations` + `nixos-rebuild switch --rollback` |

But you don't throw away a working system to get there. The plan phases it in:

- **Phase 1 (this week):** Standalone Nix + HM on Debian. HM manages configs alongside stow. Nothing breaks.
- **Phase 2 (when ready):** NixOS cutover. The HM config is identical — only the system layer changes.

---

## Project Structure

The dotfiles repo grows a flake alongside the existing layout. Old `install/` scripts stay until Phase 2.

```
~/projects/dotfiles/
├── flake.nix                     # NEW: top-level flake
├── flake.lock                    # GENERATED
├── lib/
│   ├── themes.nix                # NEW: palette definitions + config generators
│   └── default.nix               # NEW: lib exports
├── modules/
│   ├── home-manager/
│   │   ├── default.nix           # NEW: imports all HM modules
│   │   ├── git.nix               # NEW: replaces base/git/
│   │   ├── zsh.nix               # NEW: replaces base/zsh/
│   │   ├── helix.nix             # NEW: replaces base/helix/
│   │   ├── ghostty.nix           # NEW: replaces base/ghostty/
│   │   ├── hyprland.nix          # NEW: replaces base/hypr/
│   │   ├── mako.nix              # NEW: replaces base/mako/
│   │   ├── fuzzel.nix            # NEW: replaces base/fuzzel/
│   │   ├── btop.nix              # NEW: replaces base/btop/
│   │   ├── pi.nix                # NEW: Pi agent config (runtime install)
│   │   ├── theme.nix             # NEW: theme selection + activation
│   │   └── packages.nix          # NEW: user-level packages from nixpkgs
│   └── nixos/
│       ├── default.nix           # NEW: shared NixOS config (Phase 2)
│       ├── desktop.nix           # NEW: desktop profile (Hyprland, Steam)
│       └── server.nix            # NEW: server profile (datacore)
├── home/
│   └── scott/
│       └── zord.nix              # NEW: zord-specific HM config + theme choice
├── hosts/
│   ├── zord/
│   │   └── configuration.nix     # NEW: NixOS config for zord (Phase 2)
│   └── datacore/
│       └── configuration.nix     # NEW: NixOS config for datacore (Phase 2)
├── install/                      # STAYS: old scripts, unchanged until Phase 2
├── base/                         # SHRINKS: one stow package deleted per migrated module
├── themes/                       # STAYS: source data for lib/themes.nix
├── bin/                          # MOSTLY STAYS: dot-sync, dot-doctor stay; dot-theme-set gets lighter
└── tools/                        # STAYS: uv projects + Rust, unchanged
```

---

## Phase 1 — Nix + Home Manager on Debian (zord)

### Step 1: Install Nix daemon

```bash
sh <(curl -L https://nixos.org) --daemon
```

Zero risk. Nix lives in `/nix/store/`, coexists with apt, doesn't touch `/usr/`.

**What changes on disk:** `/nix/` directory tree, `/etc/profile.d/nix.sh`, a handful of systemd services.

### Step 2: Bootstrap Home Manager (standalone)

HM in standalone mode manages `~/.config/*` without a NixOS system layer. Point it at the flake:

```bash
nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update
export NIX_PATH=$HOME/.nix-defexpr/channels:/nix/var/nix/profiles/per-user/root/channels
nix-shell '<home-manager>' -A install
# Then point it at the flake:
home-manager switch --flake ~/projects/dotfiles#scott@zord
```

This registers HM as the manager of `~/.config/*` for the listed modules — but only the modules you've written. Everything else is still managed by stow.

### Step 3: Write HM modules (one per stow package)

Each module in `modules/home-manager/<name>.nix`:

- Uses HM's `programs.*` options where they exist (git, zsh, helix, btop, mpv)
- Uses `wayland.windowManager.hyprland.*` for Hyprland
- Uses `services.*` for background daemons (mako, syncthing)
- Uses `home.file."<path>".text/source` for anything without a dedicated HM option
- Accepts a `scott.theme` parameter and generates themed configs from `lib/themes.nix`

**Current stow package → HM module mapping:**

| Stow package | HM module | HM option(s) |
| --- | --- | --- |
| `base/git/` | `modules/home-manager/git.nix` | `programs.git.*` |
| `base/zsh/` | `modules/home-manager/zsh.nix` | `programs.zsh.*` + `programs.oh-my-zsh.*` |
| `base/helix/` | `modules/home-manager/helix.nix` | `programs.helix.*` |
| `base/ghostty/` | `modules/home-manager/ghostty.nix` | `home.file.".config/ghostty/config"` |
| `base/hypr/` | `modules/home-manager/hyprland.nix` | `wayland.windowManager.hyprland.*` |
| legacy desktop bar | archived | archived |
| `base/mako/` | `modules/home-manager/mako.nix` | `services.mako.*` |
| `base/fuzzel/` | `modules/home-manager/fuzzel.nix` | `programs.fuzzel.*` |
| `base/btop/` | `modules/home-manager/btop.nix` | `programs.btop.*` |
| `base/lf/` | `modules/home-manager/lf.nix` | `programs.lf.*` |
| `base/mpv/` | `modules/home-manager/mpv.nix` | `programs.mpv.*` |
| `base/systemd/` | `modules/home-manager/systemd.nix` | `systemd.user.services.*` + `systemd.user.timers.*` |
| `base/pi/` | `modules/home-manager/pi.nix` | `home.file.".pi/agent/*"` |
| `base/claude/` | `modules/home-manager/claude.nix` | `home.file.".claude/*"` |
| `base/xdg/` | `modules/home-manager/xdg.nix` | `xdg.*` |
| `base/yt-dlp/` | `modules/home-manager/yt-dlp.nix` | `home.file.".config/yt-dlp/config"` |
| `base/zellij/` | `modules/home-manager/zellij.nix` | `programs.zellij.*` |

### Step 4: Theme system as Nix library

The theme system moves from a directory of static per-app config files to a Nix library that generates them.

```nix
# lib/themes.nix
{
  palettes = {
    catppuccin-mocha = {
      variant = "dark";
      colors = {
        rosewater = "#f5e0dc";
        flamingo  = "#f2cdcd";
        pink      = "#f5c2e7";
        mauve     = "#cba6f7";
        red       = "#f38ba8";
        maroon    = "#eba0ac";
        peach     = "#fab387";
        yellow    = "#f9e2af";
        green     = "#a6e3a1";
        teal      = "#94e2d5";
        sky       = "#89dceb";
        sapphire  = "#74c7ec";
        blue      = "#89b4fa";
        lavender  = "#b4befe";
        text      = "#cdd6f4";
        subtext1  = "#bac2de";
        subtext0  = "#a6adc8";
        overlay2  = "#9399b2";
        overlay1  = "#7f849c";
        overlay0  = "#6c7086";
        surface2  = "#585b70";
        surface1  = "#45475a";
        surface0  = "#313244";
        base      = "#1e1e2e";
        mantle    = "#181825";
        crust     = "#11111b";
      };
    };
    catppuccin-latte = { ... };
  };

  # Per-app config generators
  generators = {
    tabBar = palette: { ... };  # returns EWM tab-bar styling
    ghostty = palette: { ... }; # returns INI string
    hyprland = palette: { ... }; # returns color variables section
    mako = palette: { ... };     # returns config text
    ...
  };

  # Full theme derivation: given a palette, produce all app configs
  mkTheme = palette: {
    tabBarCSS = generators.tabBar palette;
    ghosttyConf = generators.ghostty palette;
    hyprColors = generators.hyprland palette;
    ...
  };
}
```

Each HM module calls the appropriate generator and writes the result to the right config path via `home.file`.

**Theme switching at runtime:** Since `home-manager switch` is too slow for a keybind toggle, the system works in two layers:

1. **HM writes all configs** for the currently-selected theme (declared in `home/scott/zord.nix`)
2. **A lightweight runtime switcher** (a slimmed-down `dot-theme-set`) swaps symlinks for the active app configs without calling HM

This means switching themes is a sub-second operation, but the Nix config ensures correctness on rebuild.

### Step 5: One-by-one migration (stow → HM)

For each stow package:

1. Write the HM module
2. `home-manager switch --flake .#scott@zord` — HM writes the config
3. Remove the stow entry from `base/<name>/` stow package (or exclude it in the profile)
4. `dot-restow` — stow no longer manages those files
5. Verify the app still works

**Beat this order:**

1. `git` — trivial, one file, no runtime effects
2. `zsh` — replaces `.zshrc`, `.zprofile`, `.zshrc.d/`
3. `helix` — replaces `config.toml` + `languages.toml`
4. `ghostty` — replaces `config`
5. `btop`, `fuzzel` — stateless configs, easy
6. `mako` — service, but HM handles `systemd.user.services.mako`
7. `hyprland` — the big one: monitors, keybinds, windows rules, theme colors
8. `systemd` user services + timers
9. `hyprland` — the big one: monitors, keybinds, windows rules, theme colors
10. `systemd` user services + timers
11. `pi`, `claude`, `xdg`, `yt-dlp`, `zellij` — stragglers

### Step 6: Remove old install scripts (Phase 1 completion)

When every stow package has an HM equivalent and every package in `01-core.sh` is in `home.packages` or `environment.systemPackages`, the old `install/` directory becomes dead code. Don't delete it — just stop using it. The `README.md` gets updated.

At this point you have a Debian system that is fully configured by Nix + HM, and the only thing keeping you on Debian is the kernel and init system.

---

## Phase 2 — Full NixOS Cutover

### Step 7: Add NixOS modules

```nix
# modules/nixos/desktop.nix
{ config, pkgs, ... }: {
  imports = [
    ./modules/home-manager  # re-use the same HM config!
  ];

  # Steam
  programs.steam.enable = true;
  nixpkgs.config.allowUnfree = true;

  # Hyprland as system compositor
  programs.hyprland.enable = true;

  # System packages (things HM can't install)
  environment.systemPackages = with pkgs; [
    docker docker-compose
    restic
    btrfs-progs
    ...
  ];

  # Boot
  boot.loader.systemd-boot.enable = true;
}
```

The HM config from Phase 1 is imported directly into the NixOS config. Nothing changes in how your user environment works — only the system layer changes.

### Step 8: Write host configurations

```nix
# hosts/zord/configuration.nix
{ config, pkgs, ... }: {
  imports = [
    ../../modules/nixos/desktop.nix
  ];

  # zord hardware
  boot.initrd.availableKernelModules = [ ... ];
  boot.kernelModules = [ ... ];

  networking.hostName = "zord";
  networking.networkmanager.enable = true;

  # Steam needs unfree
  nixpkgs.config.allowUnfree = true;

  # Users
  users.users.scott = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "networkmanager" ];
  };

  # Home Manager as a NixOS module
  home-manager.users.scott = import ../../home/scott/zord.nix;
}
```

### Step 9: NixOS install

```bash
# From a NixOS live USB
sudo nixos-install --flake ~/projects/dotfiles#zord
```

Or, for the in-place migration path (Debian → NixOS on the same machine), use `nixos-anywhere` or a fresh install with the flake as the config.

---

## What Stays on Debian

Some things don't benefit from Nix:

| Thing | Why it stays | Where |
| --- | --- | --- |
| Docker compose stacks | Distro-agnostic, already declarative | `~/projects/datacore-config/stacks/` |
| `tools/` Python (uv) | uv manages its own deps, Nix would just provide `uv` | `~/projects/dotfiles/tools/` |
| `tools/window-picker` (Rust) | Cargo manages its own deps | `~/projects/dotfiles/tools/` |
| Pi coding agent | npm-based, config managed by HM but install stays as post-bootstrap step | `~/.pi/` |
| Syncthing | Syncthing's own config can be HM-managed, but runtime state is synced data | `~/.config/syncthing/` |

---

## What Changes on zord

After Phase 1 (`home-manager switch --flake .#scott@zord`):

| Aspect | Before | After |
| --- | --- | --- |
| Package install | `apt`, `curl | sh`,`cargo install` | `nix-env`, HM `home.packages` |
| Config files | stow-managed in `base/<name>/` | HM-generated in `~/.config/<name>/` |
| Theme switch | `dot-theme-set` symlinks static files | HM generates files from palette; slimmed `dot-theme-set` swaps symlinks |
| Shell init | `.zshrc` from stow | `programs.zsh` in HM |
| Rollback | `git revert` + `dot-restow` | `home-manager generations` + rollback |
| New machine | `./bootstrap.sh` + `./install.sh` | `home-manager switch --flake .#scott@<host>` |

---

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| HM writes overlap with existing stow files | HM's managed paths are explicitly scoped; stow won't touch paths HM claims. Migrate one at a time and verify.
| Flake.nix syntax errors lock out home-manager | Test with `nix flake check` before `home-manager switch`. Keep old install/ as fallback.
| Theme generator produces bad config | HM writes to temp paths first; review before symlinking. `dot-doctor` validates critical configs.
| HM module doesn't exist for an app | Fall back to `home.file."<path>".source` which copies a static file — same as stow but managed by HM.
| NixOS GPG/SSH agent socket paths differ | HM `home.sessionVariables` normalizes XDG paths. Test SSH agent forwarding before cutover.
| Docker compose stacks need system NixOS Docker | Enable `virtualisation.docker.enable` in the NixOS module. Compose files are unchanged.
| IB Gateway needs system user + Xvfb | Custom NixOS module in Phase 2. For Phase 1, IB Gateway stays managed by existing Debian scripts.
