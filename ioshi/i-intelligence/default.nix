{
  imports = [
    # Core — always enabled
    ./theme.nix
    ./emacs.nix
    ./git.nix
    ./zsh.nix
    ./ghostty.nix
    ./packages.nix
    ./swaylock.nix
    ./xdg.nix
    ./standalone.nix
    ./syncthing.nix
    ./btop.nix
    ./lf.nix
    ./mpv.nix
    ./yt-dlp.nix
    ./systemd.nix
    ./pi.nix
    ./zellij.nix

    # Optional — enable as needed per machine
    # ./hyprland.nix
    # ./mako.nix
    # ./fuzzel.nix

    # claude.nix is NOT activated: as written it writes `home.file
    # ".claude/settings.json".text = builtins.toJSON {}`, an empty object.
    # Activating it would blow away the live settings.json (model choice,
    # every PreToolUse/PostToolUse/... hook wired to zellaude-hook.sh,
    # enabledPlugins, tui) with `{}`, and it is quite possibly this exact
    # session's live settings.json. base/claude is therefore left in place
    # and stowed. See task-10-report.md.
    # ./claude.nix
  ];

  # Give `home-manager` a CLI after the first bootstrap switch.
  programs.home-manager.enable = true;
}
