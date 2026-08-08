{ config, lib, ... }:

{
  options.scott.zellij.enable = lib.mkEnableOption
    "zellij with the zellaude bar, deployed live from ioshi/i-intelligence/zellij";

  config = lib.mkIf config.scott.zellij.enable {
    # Package only — no `settings`: the kdl files in
    # ioshi/i-intelligence/zellij are the single source of truth, and
    # zellaude writes to its own settings json (a store copy would be
    # read-only). enableZshIntegration stays off; it would auto-start
    # zellij in every interactive shell.
    programs.zellij.enable = true;

    # One live symlink for the whole config dir (same pattern as the
    # emacs lisp dir). HM recreates it every rebuild, so plugin upgrades
    # can't strand a stale hand-made link.
    xdg.configFile."zellij".source = config.lib.file.mkOutOfStoreSymlink
      "${config.scott.dotfiles.path}/ioshi/i-intelligence/zellij";

    # SSH logins land in the persistent session. Guards: never inside an
    # existing zellij, never for TRAMP (TERM=dumb). Not `exec`: detaching
    # should drop to a plain shell, not close the connection.
    programs.zsh.initContent = lib.mkAfter ''
      if [[ -n "$SSH_CONNECTION" && -z "$ZELLIJ" && "$TERM" != "dumb" ]]; then
        zellij attach --create main
      fi
    '';
  };
}
