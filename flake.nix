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
      # Only devShell + formatter use this; the NixOS systems build their own
      # pkgs (with the overlay) via nixpkgsModule.
      pkgs = nixpkgs.legacyPackages.${system};

      dotfilesLib = import ./lib;

      sharedSpecialArgs = { inherit dotfilesLib; };

      # Applied to both NixOS systems; Home Manager inherits it via
      # useGlobalPkgs. This is what actually gets the emacs-overlay onto the
      # machines (the top-level `pkgs` below is only for devShell/formatter).
      nixpkgsModule = {
        nixpkgs.overlays = [ emacs-overlay.overlays.default ];
        nixpkgs.config.allowUnfree = true;
        nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];
      };

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
      # --- NixOS configurations ---
      nixosConfigurations = {
        # HP 15-ef2013dx — backup machine
        zord-old = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = sharedSpecialArgs // { inherit ewm; };
          modules = [
            ./hosts/zord-old/configuration.nix
            nixpkgsModule
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
            nixpkgsModule
            disko.nixosModules.disko
            home-manager.nixosModules.home-manager
            hmModule
          ];
        };
      };

      # --- Disko configurations (declarative disk partitioning) ---
      diskoConfigurations = {
        zord = import ./ioshi/hi-hardware/disko/eminix.nix;
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