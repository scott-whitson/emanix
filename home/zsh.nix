{ config, lib, ... }:

let
  # The env every emanix surface exports, defined once (lib/emanix-env.nix) and
  # used by the two surfaces this file owns: the login shell's variables and the
  # systemd user manager's.
  emanixEnv = (import ../lib/emanix-env.nix { inherit lib; }).mkEmanixEnv {
    src = config.emanix.src;
    role = config.emanix.role;
    theme = config.emanix.theme;
  };
in

{
  programs.zsh = {
    enable = true;
    # Lock the legacy dotDir (home dir) to silence the 26.05 default-change
    # warning without moving zsh's dotfiles. Revisit (XDG) in emanix v2.
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
    } // emanixEnv;

    initContent = ''
      # Prepend hostname in parentheses when SSH'd in, so you always
      # know which machine you're on.
      if [[ -n "$SSH_CLIENT" ]]; then
        PROMPT='(%m) %{$fg_bold[green]%}%p %{$fg[cyan]%}%c %{$fg_bold[blue]%}$(git_prompt_info) %{$reset_color%}'
      fi

      # Helper scripts live in the CONSUMER's checkout, not the distro's —
      # the distro ships no bin/. UNSET on a host built from the
      # distribution alone; a consumer that keeps helper scripts sets
      # emanix.src.binDir and gets them first on PATH.
      ${lib.optionalString (config.emanix.src.binDir != null) ''
        export PATH="$EMANIX_BIN_DIR:$PATH"
      ''}

      # Local bin
      export PATH="$HOME/.local/bin:$PATH"

      # NO fzf, zoxide or starship hooks. All three were `command -v' (or
      # /usr/share) guarded sources carried over from the stow/apt era, and
      # none of the three has ever been in this flake -- so all three were
      # guards that could only ever take their false branch. "If it is not in
      # the flake, it does not exist" has to cut both ways or the shell init
      # becomes a list of things that might be true somewhere. Removed
      # 2026-09-10. Reinstate the hook and the package together, or neither.
      #
      # starship additionally contradicted the oh-my-zsh robbyrussell theme
      # set above: had it ever been installed, the last prompt assignment
      # would have won and the declared theme would have been a no-op.

      # Theme state markers. The new path first, then the pre-rename one
      # (migrated by emanix/theme-init) so a shell that starts before Emacs
      # has migrated the marker does not lose the theme.
      if [[ -f "$HOME/.config/emanix/active-theme" ]]; then
        export ACTIVE_THEME="$(cat "$HOME/.config/emanix/active-theme")"
      elif [[ -f "$HOME/.config/dotfiles/active-theme" ]]; then
        export ACTIVE_THEME="$(cat "$HOME/.config/dotfiles/active-theme")"
      fi

      # Refresh PATH from Nix profiles on every shell
      if [[ -d /nix/var/nix/profiles/default/bin ]]; then
        export PATH="/nix/var/nix/profiles/default/bin:$PATH"
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
          # Reuse a visible frame instead of paying for a new one: measured on
          # whistle 2026-10-27, make-frame cost 274 ms cold against 34 ms warm,
          # and the cold frame is the whole wait before the first keypress.
          # `framep' is `t' for a tty frame, so the predicate skips tty and
          # invisible frames -- the daemon keeps a stale invisible pgtk one.
          local raise='(let ((f (seq-find (lambda (f) (and (not (eq (framep f) (quote t))) (eq (frame-parameter f (quote visibility)) (quote t)))) (frame-list)))) (if f (progn (select-frame-set-input-focus f) (raise-frame f) t) (error "ec: no frame")))'
          if emacsclient -d "$WAYLAND_DISPLAY" -e "$raise" >/dev/null 2>&1; then
            [[ $# -eq 0 ]] || emacsclient -d "$WAYLAND_DISPLAY" "$@"
          else
            emacsclient -c -d "$WAYLAND_DISPLAY" "$@"
          fi
        else
          emacsclient -c "$@"
        fi
      }
      et() { emacsclient -t "$@"; }
    '';
  };

  # The same values, exported to the SYSTEMD USER MANAGER as well as the
  # shell. A systemd user service does not start from a login shell, so
  # programs.zsh.sessionVariables above never reaches one — and the Emacs
  # daemon is exactly such a service. Without this, elisp that resolves
  # $EMANIX_BIN_DIR (the EWM firefox slot) gets an empty string and expands
  # to a bare relative path — and emanix-welcome.el's $EMANIX_DOTFILES read
  # would go the same way for a daemon-only session.
  #
  # The daemon is the case that must work, not the one that may be missed, so
  # the reason is a property of the daemon rather than of any one reader. Both
  # EMANIX_BIN_DIR and EMANIX_DOTFILES are UNSET when their option is null —
  # a host built from the distribution alone — and a consumer that keeps
  # helper scripts sets emanix.src.binDir to get them first on PATH.
  #
  # The list itself is in lib/emanix-env.nix, shared with the shell's copy
  # above and with the EWM login session in modules/ewm.nix. It used to be
  # spelled out three times, and the copies had already drifted: this one was
  # missing EMANIX_ROLE, and the EWM session was missing EMANIX and
  # EMANIX_ROLE too. The failure is silent, because every reader is an elisp
  # `getenv' that returns nil for a variable nobody exported.
  #
  # HM writes these to ~/.config/environment.d/, which the user manager reads
  # at start: changing them needs `systemctl --user daemon-reload` plus a
  # restart of the affected service, not just a rebuild.
  systemd.user.sessionVariables = emanixEnv;
}
