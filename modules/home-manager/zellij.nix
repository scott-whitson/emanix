{ config, lib, pkgs, ... }:

{
  programs.zellij = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      theme = "catppuccin-mocha";
      default_mode = "normal";
      mouse_mode = false;
      pane_frames = false;
      simplified_ui = true;
      scrollback_buffer_size = 10000;
      copy_command = "wl-copy";
      default_shell = "zsh";
      on_force_close = "quit";
      keybinds = {
        normal = {
          "bind \"Ctrl t\"" = { action = "NewTab"; };
          "bind \"Ctrl n\"" = { action = "NewPane"; direction = "Down"; };
          "bind \"Ctrl p\"" = { action = "NewPane"; direction = "Right"; };
          "bind \"Ctrl w\"" = { action = "CloseFocus"; };
          "bind \"Ctrl h\"" = { action = "MoveFocus"; direction = "Left"; };
          "bind \"Ctrl l\"" = { action = "MoveFocus"; direction = "Right"; };
          "bind \"Ctrl k\"" = { action = "MoveFocus"; direction = "Up"; };
          "bind \"Ctrl j\"" = { action = "MoveFocus"; direction = "Down"; };
          "bind \"Alt h\"" = { action = "Resize"; direction = "Left"; };
          "bind \"Alt l\"" = { action = "Resize"; direction = "Right"; };
          "bind \"Alt k\"" = { action = "Resize"; direction = "Up"; };
          "bind \"Alt j\"" = { action = "Resize"; direction = "Down"; };
          "bind \"Ctrl \\\\\"" = { action = "SwitchToMode"; mode = "session"; };
        };
      };
    };
  };
}