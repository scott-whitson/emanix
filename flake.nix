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

      # Compose an eminix host: profile (os+i) + its hi layer.
      mkHost = import ./lib/mkHost.nix {
        inherit nixpkgs home-manager ewm nixpkgsModule hmModule sharedSpecialArgs system;
      };
    in
    {
      # --- NixOS configurations — eminix instances ---
      nixosConfigurations = {
        # HP 15-ef2013dx — backup machine
        zord-old = mkHost {
          hostName = "zord-old";
          hardware = ./ioshi/hi-hardware/hp-15-ef2013dx.nix;
          extraModules = [ ./hosts/zord-old/configuration.nix ];
        };

        # ThinkPad T14 Gen 5 AMD — daily driver (the eminix platform)
        eminix = mkHost {
          hostName = "eminix";
          hardware = ./ioshi/hi-hardware/lenovo-t14-gen5-amd.nix;
          extraModules = [
            ./hosts/eminix/configuration.nix
            disko.nixosModules.disko
            ./ioshi/hi-hardware/disko/eminix.nix
          ];
        };
      };

      # --- Disko configurations (declarative disk partitioning) ---
      diskoConfigurations = {
        eminix = import ./ioshi/hi-hardware/disko/eminix.nix;
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