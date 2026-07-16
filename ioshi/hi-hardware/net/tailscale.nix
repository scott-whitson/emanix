{ ... }:
{
  # Tailscale over self-hosted headscale (docker on datacore; no browser login).
  # Fresh-install join ritual:
  #   datacore$ docker exec headscale headscale preauthkeys create --user 1 --expiration 1h
  #   host$     echo '<key>' | sudo tee /var/lib/tailscale-authkey
  #             sudo systemctl restart tailscaled-autoconnect
  # authKeyFile moves to agenix in Phase D.
  services.tailscale = {
    enable = true;
    authKeyFile = "/var/lib/tailscale-authkey";
    extraUpFlags = [ "--login-server=https://headscale.stonewallmapletree.com" ];
  };
  services.resolved.enable = true;
}
