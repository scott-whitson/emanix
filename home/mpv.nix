{ config, lib, pkgs, ... }:

{
  # GUI-only: programs.mpv.enable unconditionally pulls in the mpv package,
  # which would otherwise defeat packages.nix's `lib.optional config.emanix.gui
  # mpv` gate on headless hosts.
  config = lib.mkIf config.emanix.gui {
    programs.mpv = {
      enable = true;
      config = {
        # base/mpv/.config/mpv/mpv.conf's one line — carried over verbatim.
        ytdl-format = "bestvideo[height<=?1080][vcodec!=?vp9]+bestaudio/best";

        volume = 60;
        volume-max = 200;
        cache = "yes";
        cache-secs = 300;
        demuxer-max-bytes = "150M";
        demuxer-max-back-bytes = "75M";
        hwdec = "auto-safe";
        profile = "gpu-hq";
        scale = "ewa_lanczossharp";
        cscale = "ewa_lanczossharp";
        video-sync = "display-resample";
        interpolation = "yes";
        tscale = "oversample";
        native-fs = "yes";
      };
      bindings = {
        "Ctrl+h" = "cycle ao";
        "Ctrl+l" = "cycle sub";
        "Ctrl+v" = "cycle sub-visibility";
        "Ctrl+s" = "screenshot";
        "f" = "cycle fullscreen";
        "m" = "cycle mute";
        "9" = "add volume -2";
        "0" = "add volume 2";
      };
      scripts = with pkgs.mpvScripts; [
        mpris
        uosc
      ];
    };
  };
}
