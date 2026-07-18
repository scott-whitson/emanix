{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    lfs.enable = true;
    # For local overrides (e.g. work email), users keep ~/.gitconfig.local
    includes = [{ path = "~/.gitconfig.local"; }];
    settings = {
      user = {
        name = "Scott Whitson";
        email = "scott@scottwhitson.com";
      };
      core = { autocrlf = "input"; };
      init = { defaultBranch = "main"; };
      pull = { rebase = true; };
      push = { autoSetupRemote = true; };
      rebase = { autoStash = true; };
      url = {
        "ssh://git@datacore:2222/" = { insteadOf = "ssh://datacore/"; };
      };
      # git config [alias] section — moved here from the deprecated
      # top-level programs.git.aliases (renamed to programs.git.settings.alias).
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
}
