{
  description = "scott's dotfiles — Nix flake (NixOS + EWM + Home Manager)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ewm = {
      url = "https://codeberg.org/ezemtsov/ewm/archive/master.tar.gz";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      emacs-overlay,
      ewm,
      disko,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ emacs-overlay.overlays.default ];
      };

      lib = import ./lib { inherit pkgs; };

      sharedSpecialArgs = { dotfilesLib = lib; };

      hmModule = {
        home-manager = {
          extraSpecialArgs = sharedSpecialArgs;
          useGlobalPkgs = true;
          useUserPackages = true;
          users.scott = {
            imports = [ ./home/scott/default.nix ];
          };
        };
      };
    in
    {
      # --- Standalone Home Manager ---
      homeConfigurations = {
        "scott@zord" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./modules/home-manager
            ./home/scott/default.nix
          ];
          extraSpecialArgs = sharedSpecialArgs;
        };
      };

      # --- NixOS configurations ---
      nixosConfigurations = {
        # HP 15-ef2013dx — backup machine
        zord-old = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = sharedSpecialArgs // { inherit ewm; };
          modules = [
            ./hosts/zord-old/configuration.nix
            home-manager.nixosModules.home-manager
            hmModule
          ];
        };

        # ThinkPad T14 Gen 5 AMD — daily driver
        zord = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = sharedSpecialArgs // { inherit ewm; };
          modules = [
            ./hosts/zord/configuration.nix
            disko.nixosModules.disko
            home-manager.nixosModules.home-manager
            hmModule
          ];
        };
      };

      # --- Disko configurations (declarative disk partitioning) ---
      diskoConfigurations = {
        zord = import ./hosts/zord/disko.nix;
      };

      # --- Dev shell ---
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nixd
          nixpkgs-fmt
          deadnix
          statix
        ];
      };

      formatter.${system} = pkgs.nixpkgs-fmt;
    };
}