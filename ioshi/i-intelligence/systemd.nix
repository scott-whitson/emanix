{ config, lib, pkgs, ... }:

{
  systemd.user.services = {
    # Other user services currently managed by base/systemd/* will be migrated
    # here as they are ported from stow to HM.
  };

  systemd.user.timers = {
    # dot-sync timer (managed by profile — only enabled on machines that can push)
    # For pull-only machines, this timer is not created.
    "dot-sync" = lib.mkIf config.scott.dotfiles.enableSync {
      Unit = {
        Description = "Sync dotfiles to remote";
      };
      Timer = {
        OnBootSec = "5min";
        OnUnitActiveSec = "15min";
        Persistent = true;
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
