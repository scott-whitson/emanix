{ config, lib, pkgs, ... }:

{
  # zord-old — HP 15-ef2013dx (Ryzen 5 5500U, 32 GB)
  # This machine serves as the NixOS pilot before the T14 arrives.
  # After the T14 takes over as "zord", this becomes the backup/spare.
  #
  # Home Manager is imported from flake.nix via home-manager.nixosModules.

  networking.hostName = "zord-old";

  imports = [
    ../../modules/nixos/hardware/hp-15-ef2013dx.nix
    ../../modules/nixos/ewm.nix
    ../../modules/nixos/desktop.nix
  ];

  # Zsh — must be enabled at NixOS level so the shell is in PATH.
  programs.zsh.enable = true;

  # Auto-login on the console: the LUKS passphrase already gates the machine,
  # and the EWM launch hook (modules/nixos/ewm.nix) takes over tty1.
  services.getty.autologinUser = "scott";

  # SSH — remote administration from datacore (key) or LAN (password).
  services.openssh.enable = true;
  users.users.scott.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHeRiEMkgSu+cBXTs7ekkJdT5JzJYCfDadrpFgDFn560 scott@datacore"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINW1gKUfmcHDWf02SHUpZuIZEqq7qk4IJfmd8hlLAUQi swhitson-11l"
  ];

  # Tailscale — datacore and swhitson-11l are MagicDNS names, not LAN DNS.
  # Control plane is self-hosted headscale (docker on datacore); there is
  # no browser login. Fresh-install join ritual:
  #   datacore$ docker exec headscale headscale preauthkeys create --user 1 --expiration 1h
  #   here$     echo '<key>' | sudo tee /var/lib/tailscale-authkey
  #             sudo systemctl restart tailscaled-autoconnect
  services.tailscale = {
    enable = true;
    authKeyFile = "/var/lib/tailscale-authkey";
    extraUpFlags = [ "--login-server=https://headscale.stonewallmapletree.com" ];
  };
  services.resolved.enable = true;

  # Syncthing — pi session sync with datacore (folder "pi-agent").
  # Device IDs are public keys, safe to commit. Per-machine files
  # (auth.json, HM-owned settings.json/AGENTS.md, themes/) are excluded
  # by the .stignore that pi.nix writes into the folder.
  # Pairing is two-sided: datacore must also add this host's device ID
  # and share the folder (REST API or GUI on datacore:8384).
  services.syncthing = {
    enable = true;
    user = "scott";
    group = "users";
    dataDir = "/home/scott";
    configDir = "/home/scott/.local/state/syncthing";
    openDefaultPorts = true;
    overrideDevices = true;
    overrideFolders = true;
    settings = {
      devices.datacore.id =
        "FXOPHIF-EMJAP6C-CLI6PB4-HCLUDMK-RJ3PXLE-GIV4IJ7-3NMTE35-YHRNIAI";
      folders.pi-agent = {
        id = "pi-agent";
        label = "pi-agent";
        path = "/home/scott/.pi/agent";
        devices = [ "datacore" ];
      };
      folders.docs = {
        id = "docs";
        label = "docs";
        path = "/home/scott/docs";
        devices = [ "datacore" ];
      };
    };
  };

  # User
  users.users.scott = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" "video" ];
    shell = pkgs.zsh;
  };

  # Locale
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # This value determines the NixOS release the config is compatible with.
  system.stateVersion = "24.11";
}