{ config, lib, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    # Lock the legacy dotDir (home dir) to silence the 26.05 default-change
    # warning without moving zsh's dotfiles. Revisit (XDG) in eminix v2.
    dotDir = config.home.homeDirectory;
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
      EMINIX = "$HOME/projects/eminix";
      # Interactive convenience only — nothing in the repo reads it.
      EMINIX_ROLE = config.eminix.role;
    };

    initContent = ''
      # eminix helpers on PATH
      export PATH="$EMINIX/bin:$PATH"

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

      # Emacs clients. ec prefers the Wayland display: pgtk emacs over X11 is
      # unsupported (warns, sporadic crashes) and picks X11 whenever $DISPLAY
      # is set — which WSLg always does alongside $WAYLAND_DISPLAY.
      ec() {
        if [[ -n "$WAYLAND_DISPLAY" ]]; then
          # WSLg's compositor can die while its socket FILES survive (seen
          # 2026-07-26). pgtk emacs KILLS THE WHOLE DAEMON when a frame
          # can't open its display, so probe liveness first: WSLg's X0
          # socket vanishes exactly when the compositor is dead.
          if [[ -d /mnt/wslg ]] && [[ ! -S /tmp/.X11-unix/X0 ]]; then
            echo "ec: WSLg display looks dead (no /tmp/.X11-unix/X0) — restart the distro:" >&2
            echo "    wsl --terminate <distro> (from PowerShell, then reopen)" >&2
            return 1
          fi
          # Rarer sibling failure: the compositor is ALIVE (X0 present, frames
          # create, frame-visible-p says t) but weston hit an I/O error mapping
          # /mnt/shared_memory at session start and so set use_gfxredir = 0 —
          # killing the channel that carries window pixels to Windows. Frames
          # then open, take focus, get a taskbar button and never paint; the
          # window title gains a "[WARN:COPY MODE]" prefix. Cost a morning on
          # 2026-08-10 because every symptom points at emacs/GlazeWM/monitors
          # instead. weston logs the value once per session and /mnt/wslg is
          # tmpfs, so this always describes the CURRENT session.
          if [[ "$(grep -a 'use_gfxredir' /mnt/wslg/weston.log 2>/dev/null | tail -1)" == *"= 0"* ]]; then
            echo "ec: WSLg has gfxredir disabled — a GUI frame would open but never paint." >&2
            echo "    weston failed to map /mnt/shared_memory when this session started." >&2
            echo "    Fix: wsl --shutdown   (from PowerShell, then reopen)" >&2
            echo "    Note: wsl --terminate is NOT enough, nor is killing msrdc.exe." >&2
            echo "    Until then use: et   (terminal frame, same daemon, unaffected)" >&2
            return 1
          fi
          emacsclient -c -d "$WAYLAND_DISPLAY" "$@"
        else
          emacsclient -c "$@"
        fi
      }
      et() { emacsclient -t "$@"; }
    '';
  };
}
