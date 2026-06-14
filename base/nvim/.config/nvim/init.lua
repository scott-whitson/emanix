-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

-- Dotfiles theme opt-in (see themes/*/nvim.lua)
pcall(require, 'dotfiles-theme')
