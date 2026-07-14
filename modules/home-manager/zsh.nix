{ config, lib, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [
        "git"
        "sudo"
        "systemd"
        "command-not-found"
      ];
      custom = "$ZSH/custom";
    };

    sessionVariables = {
      EDITOR = "emacsclient";
      VISUAL = "emacsclient";
      PAGER = "less";
      DOTFILES = "$HOME/dotfiles";
      DOTFILES_PROFILE = "desktop";
    };

    initContent = ''
      # dotfiles helpers on PATH
      export PATH="$DOTFILES/bin:$PATH"

      # Local bin
      export PATH="$HOME/.local/bin:$PATH"

      # fzf (installed by Nix or apt, source if available)
      if [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
        source /usr/share/fzf/key-bindings.zsh
        source /usr/share/fzf/completion.zsh
      fi

      # zoxide
      if command -v zoxide &>/dev/null; then
        eval "$(zoxide init zsh)"
      fi

      # Dotfiles theme state markers
      [[ -f "$HOME/.config/dotfiles/active-theme" ]] && \
        export ACTIVE_THEME="$(cat "$HOME/.config/dotfiles/active-theme")"

      # Refresh PATH from Nix profiles on every shell
      if [[ -d /nix/var/nix/profiles/default/bin ]]; then
        export PATH="/nix/var/nix/profiles/default/bin:$PATH"
      fi

      # Starship prompt (if installed)
      if command -v starship &>/dev/null; then
        eval "$(starship init zsh)"
      fi
    '';
  };
}