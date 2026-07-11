{ config, lib, pkgs, ... }:

{
  # Claude Code config
  home.file.".claude/settings.json" = {
    text = builtins.toJSON { };
  };
}