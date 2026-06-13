# base/zsh/.zshrc.d/dotfiles.zsh — exports DOTFILES and prepends $DOTFILES/bin to PATH
# Stowed to ~/.zshrc.d/dotfiles.zsh; sourced by the base .zshrc loop.

# Point to the dotfiles checkout. Follows symlinks to a real directory.
export DOTFILES="${DOTFILES:-$HOME/dotfiles}"

# Prepend $DOTFILES/bin so dot-* helpers win over anything else on PATH.
if [[ -d "$DOTFILES/bin" ]] && [[ ":$PATH:" != *":$DOTFILES/bin:"* ]]; then
    export PATH="$DOTFILES/bin:$PATH"
fi
