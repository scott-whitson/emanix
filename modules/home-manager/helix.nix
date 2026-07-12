{ config, lib, pkgs, ... }:

let
  theme = config.lib.theme;
  palette = theme.palettes.catppuccin-mocha;
in
{
  programs.helix = {
    enable = true;

    settings = {
      theme = "catppuccin_mocha";

      editor = {
        line-number = "relative";
        cursorline = true;
        auto-save = { after-delay.enable = true; };
        bufferline = "multiple";

        cursor-shape = {
          insert = "bar";
          normal = "block";
          select = "underline";
        };

        indent-guides = { render = true; };

        statusline = {
          left = [ "mode" "spinner" "file-name" "file-modification-indicator" ];
          right = [ "diagnostics" "selections" "position" "file-type" ];
        };
      };

      keys.normal = {
        space.space = "file_picker";
        space.w = ":w";
        space.q = ":q";
        space.x = ":buffer-close";
        space.f = "file_picker_in_buffer_directory";
      };
    };

    languages = [
      {
        name = "markdown";
        roots = [ ".zk" ];
        language-servers = [ "zk" ];
        auto-format = true;
      }
      {
        name = "nix";
        auto-format = true;
        formatter = { command = "nixpkgs-fmt"; };
        language-servers = [ "nixd" ];
      }
    ];
  };
}