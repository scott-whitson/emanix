{ config, lib, ... }:

{
  options.eminix.git = {
    userName = lib.mkOption {
      type = lib.types.str;
      default = "eminix user";
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
          name = config.eminix.git.userName;
          email = config.eminix.git.userEmail;
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
  };
}
