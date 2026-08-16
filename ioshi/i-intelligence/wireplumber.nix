{ config, lib, ... }:

{
  config = lib.mkIf config.eminix.gui {
    # Silences ACP-related boot warnings on AMD ("Failed to create
    # 'api.alsa.acp.device' device", "Path Mic ACP LED is not a volume or mute
    # control"). WirePlumber probes the AMD ACP platform device, which exposes a
    # non-standard LED control; the split-device feature then tries to open
    # hw:acp and fails because the ALSA ACP plugin is not available. Disabling
    # split mode skips the probe — the real cards (HDMI + HDA) still enumerate
    # normally via their PCI paths.
    xdg.configFile."wireplumber/wireplumber.conf.d/50-disable-acp-led.conf".text = ''
      monitor.alsa.properties = {
        api.alsa.split-enable = false
      }
    '';
  };
}
