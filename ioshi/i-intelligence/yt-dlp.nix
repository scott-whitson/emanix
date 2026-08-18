{ ... }:

{
  home.file.".config/yt-dlp/config" = {
    text = ''
      # yt-dlp config — managed by Home Manager
      --embed-metadata
      --embed-thumbnail
      --add-metadata
      --metadata-from-title "%(title)s"
      --output "%(title)s.%(ext)s"
      --restrict-filenames
      --no-mtime
      --sponsorblock-mark all
      --sponsorblock-remove sponsor,selfpromo
      --format "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
      --merge-output-format mkv
    '';
  };
}
