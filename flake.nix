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
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      emacs-overlay,
      ewm,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ emacs-overlay.overlays.default ];
      };

      lib = import ./lib { inherit pkgs; };

      # Shared special args for both standalone HM and NixOS HM
      sharedSpecialArgs = { dotfilesLib = lib; };
    in
    {
      # --- Standalone Home Manager (still works on Debian / Phase 1) ---
      homeConfigurations = {
        "scott@zord" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./modules/home-manager
            ./home/scott/default.nix
            # Don't import the host HM module here — it's only for NixOS.
          ];
          extraSpecialArgs = sharedSpecialArgs;
        };
      };

      # --- NixOS configurations ---
      nixosConfigurations = {
        # Datacore — headless server
        datacore = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = sharedSpecialArgs;
          modules = [
            ./hosts/datacore/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = sharedSpecialArgs;
                useGlobalPkgs = true;
                useUserPackages = true;
                users.scott = {
                  imports = [ ./home/scott/default.nix ];
                };
              };
            }
          ];
        };
        # HP 15-ef2013dx — NixOS pilot, then backup machine
        zord-old = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = sharedSpecialArgs // { inherit ewm; };
          modules = [
            ./hosts/zord-old/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = sharedSpecialArgs;
                useGlobalPkgs = true;
                useUserPackages = true;
                users.scott = {
                  imports = [ ./home/scott/default.nix ];
                };
              };
            }
          ];
        };

        # ThinkPad T14 Gen 5 AMD — daily driver (when it arrives)
        zord = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = sharedSpecialArgs // { inherit ewm; };
          modules = [
            ./hosts/zord/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = sharedSpecialArgs;
                useGlobalPkgs = true;
                useUserPackages = true;
                users.scott = {
                  imports = [ ./home/scott/default.nix ];
                };
              };
            }
          ];
        };
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