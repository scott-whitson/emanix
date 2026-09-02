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
          (import ./disko.nix { inherit host; })
          ./configuration.nix
          emanix.nixosModules.ewm
        ];
      };
    };
}
