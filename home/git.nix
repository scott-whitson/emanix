{ config, lib, ... }:

{
  options.emanix.git = {
    userName = lib.mkOption {
      type = lib.types.str;
      default = "emanix user";
      description = "Git user.name. Set per-host by the consuming flake.";
    };
    userEmail = lib.mkOption {
      type = lib.types.str;
      default = "user@example.invalid";
      description = "Git user.email. Set per-host by the consuming flake.";
    };
  };

  config = {
    programs.git = {
      enable = true;
      lfs.enable = true;
      # For local overrides (e.g. work email), users keep ~/.gitconfig.local
      includes = [{ path = "~/.gitconfig.local"; }];
      settings = {
        user = {
          name = config.emanix.git.userName;
          email = config.emanix.git.userEmail;
        };
        core = { autocrlf = "input"; };
        init = { defaultBranch = "main"; };
        pull = { rebase = true; };
        push = { autoSetupRemote = true; };
        rebase = { autoStash = true; };
        alias = {
          lg = "log --oneline --graph --decorate --all";
          st = "status -s";
          ci = "commit -v";
          co = "checkout";
          br = "branch";
          unstage = "reset HEAD --";
          last = "log -1 HEAD";
          amend = "commit --amend --no-edit";
          fixup = "commit --fixup";
          squash = "commit --squash";
        };
      };
      ignores = [
        ".DS_Store"
        "*.swp"
        "*.swo"
        "*~"
        ".direnv"
        ".envrc"
      ];
    };

    programs.diff-so-fancy = {
      enable = true;
      enableGitIntegration = true;
    };

    # `git config --global` writes $HOME/.gitconfig when it exists, and otherwise
    # the managed ~/.config/git/config -- a read-only store symlink, so the write
    # fails with "could not lock config file ... Read-only file system". Measured
    # 2026-10-29: that is what broke `gh auth login` setting up its credential
    # helper, and it breaks any `git config --global` a person or a tool runs.
    #
    # The created file MUST include the managed one. Git reads ONE global file:
    # ~/.gitconfig when it exists, and only the XDG one when it does not
    # (measured on 2.54.0; the manual's "both files are read" does not describe
    # the lookup). Creating it without the include silently drops every emanix
    # default -- aliases, user.name, the ignore list, push.autoSetupRemote.
    #
    # ponytail: a reader that passes `--global` or `--file` does not follow
    # includes, so `git config --global --get user.email` sees only this file and
    # not emanix's defaults. Git itself, and any lookup without an explicit
    # scope, do follow it -- the alias and identity above are in force for real
    # commands. Closing the gap means seeding the managed values into this file
    # and re-seeding on drift, which buys that one query at the price of a merge
    # with the user's own edits. Upgrade path if a tool ever depends on it.
    home.activation.gitconfigWritable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [[ ! -v DRY_RUN ]] && [[ ! -e "$HOME/.gitconfig" ]]; then
        printf '%s\n' \
          '# Yours: git and anything else is free to write here.' \
          '# emanix manages ~/.config/git/config (read-only) and git reads only' \
          '# ONE global file -- this one -- so the managed file is included' \
          '# below it. Anything set after the include wins over the defaults.' \
          '[include]' \
          '\tpath = ~/.config/git/config' > "$HOME/.gitconfig"
        chmod 600 "$HOME/.gitconfig"
      fi
    '';
  };
}
