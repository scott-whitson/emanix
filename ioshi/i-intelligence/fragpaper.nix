{ config, lib, pkgs, ... }:

{
  # Ported from base/systemd/.config/systemd/user/ during the stow retirement.
  # The originals hardcoded /usr/bin/pkill, /bin/sleep, /usr/bin/systemctl and
  # /bin/bash — none of which exist on NixOS, so ExecStop and the resume hook
  # had been failing silently since the migration. Now resolved from pkgs.
  config = lib.mkIf config.scott.gui {
    systemd.user.services.fragpaper = {
      Unit = {
        Description = "Fragpaper live wallpaper";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "%h/.local/share/fragpaper/target/release/fragpaper --bg-color \"#1a1b26\" --palette dark --playlist %h/.local/share/fragpaper/shaders/mandelbrot.frag:90 %h/.local/share/fragpaper/shaders/julia.frag:90 %h/.local/share/fragpaper/shaders/burningship.frag:60 %h/.local/share/fragpaper/shaders/gradient.frag:60 %h/.local/share/fragpaper/shaders/waveform.frag:45 %h/.local/share/fragpaper/shaders/mist.frag:45 ca:45 coral:60 highlife:45 morley:45 gliders:60 glidersrandom:60 rd:90 lenia:60 %h/.local/share/fragpaper/shaders/attractors.vert:%h/.local/share/fragpaper/shaders/attractors.frag:90";
        ExecStop = "${pkgs.procps}/bin/pkill -9 -f fragpaper";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = 10;
        Environment = [ "RUST_LOG=info" ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.fragpaper-resume = {
      Unit = {
        Description = "Restart fragpaper after sleep/wake";
        After = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
        ExecStart = "${pkgs.systemd}/bin/systemctl --user restart fragpaper.service";
      };
      Install.WantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target" ];
    };

    systemd.user.services.fragpaper-monitor = {
      Unit.Description = "Check if fragpaper is running and restart if not";
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'if ! ${pkgs.systemd}/bin/systemctl --user is-active --quiet fragpaper.service; then ${pkgs.systemd}/bin/systemctl --user restart fragpaper.service; fi'";
      };
    };

    systemd.user.timers.fragpaper-monitor = {
      Unit.Description = "Monitor fragpaper and restart if dead";
      Timer = {
        OnBootSec = 30;
        OnUnitActiveSec = 60;
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
