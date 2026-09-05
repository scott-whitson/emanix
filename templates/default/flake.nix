{
  description = "An emanix host";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    emanix = {
      url = "github:scott-whitson/emanix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, emanix, disko, ... }:
    let
      system = "x86_64-linux";
      host = import ./host.nix;
    in
    {
      nixosConfigurations.${host.hostName} = emanix.lib.mkHost {
        inherit (host) hostName;
        role = "workstation";
        username = "youruser";
        hardware = ./hardware-configuration.nix;
        extraModules = [
          disko.nixosModules.disko
          (emanix.lib.mkDisk {
            inherit (host) device luks filesystem swapSize;
          })
          { emanix.hardware.gpu = host.gpu; }
          ./configuration.nix
          emanix.nixosModules.ewm
        ]
        # Optional per-model tuning, only when host.nix names a module. The
        # input comes from emanix so this file needs no input of its own.
        ++ nixpkgs.lib.optional (host.hardwareModule != null)
          emanix.inputs.nixos-hardware.nixosModules.${host.hardwareModule};
      };
    };
}
