{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    lfs.enable = true;
    userName = "Scott Whitson";
    userEmail = "scott@scottwhitson.com";
    # For local overrides (e.g. work email), users keep ~/.gitconfig.local
    includes = [{ path = "~/.gitconfig.local"; }];
    extraConfig = {
      core = { autocrlf = "input"; };
      init = { defaultBranch = "main"; };
      pull = { rebase = true; };
      push = { autoSetupRemote = true; };
      rebase = { autoStash = true; };
      url = {
        "ssh://git@datacore:2222/" = { insteadOf = "ssh://datacore/"; };
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
    aliases = {
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
    diff-so-fancy = {
      enable = true;
    };
  };
}