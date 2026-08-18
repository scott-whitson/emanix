{ config, lib, ... }:

{
  options.eminix.tailscale = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Tailscale mesh VPN.";
    };
    loginServer = lib.mkOption {
      type = lib.types.str;
      default = "https://controlplane.tailscale.com";
      description = "Coordination server URL. Set to a self-hosted headscale URL when used.";
    };
  };

  config = lib.mkIf config.eminix.tailscale.enable {
    services.tailscale = {
      enable = true;
      authKeyFile = "/var/lib/tailscale-authkey";
      extraUpFlags = [ "--login-server=${config.eminix.tailscale.loginServer}" ];
    };
    services.resolved.enable = true;
  };
}
