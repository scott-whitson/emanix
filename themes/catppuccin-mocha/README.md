# Catppuccin Mocha (dark)

The dark half of the Catppuccin palette. Variant: **dark**.

## Activate

    dot-theme-set catppuccin-mocha

## Optional enhancements

- **Neovim:** install the `catppuccin/nvim` plugin in your kickstart fork for
  colors to apply. Add to `~/.config/nvim/lua/custom/plugins/catppuccin.lua`:
  ```lua
  return {
    { 'catppuccin/nvim', name = 'catppuccin', priority = 1000 },
  }
  ```
- **Obsidian:** install the community "Catppuccin" theme and edit
  `themes/catppuccin-mocha/obsidian-theme` to `Catppuccin`. Otherwise ships
  with Obsidian's default dark theme.
- **GTK apps:** `gtk.conf` sets `Adwaita-dark` by default. Replace with
  `catppuccin-mocha-mauve-standard` (or similar) if you've installed a GTK
  Catppuccin theme package from AUR.

Source: https://catppuccin.com/palette
