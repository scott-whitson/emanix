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
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , nixpkgs
    , home-manager
    , emacs-overlay
    , ewm
    , disko
    , nixos-hardware
    , agenix
    , ...
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
            # eminix instances run the system-owned EWM Emacs. mkDefault so a
            # non-EWM NixOS host (weasel) can opt out while reusing hmModule.
            scott.ewm.enable = nixpkgs.lib.mkDefault true;
          };
        };
      };

      # Compose an eminix host: profile (os+i) + its hi layer.
      mkHost = import ./lib/mkHost.nix {
        inherit nixpkgs home-manager ewm agenix nixpkgsModule hmModule sharedSpecialArgs system;
      };

      # Standalone Home-Manager homes for the foreign-distro nodes
      # (Debian datacore, Debian WSL). Same home layer as eminix, headless.
      hmPkgs = import nixpkgs {
        inherit system;
        overlays = [ emacs-overlay.overlays.default ];
        config.allowUnfree = true;
        # Parity with nixpkgsModule: a future gui=true standalone home would
        # otherwise fail eval on bitwarden-desktop's electron.
        config.permittedInsecurePackages = [ "electron-39.8.10" ];
      };
      mkHome = profile:
        home-manager.lib.homeManagerConfiguration {
          pkgs = hmPkgs;
          extraSpecialArgs = sharedSpecialArgs;
          modules = [
            ./home/scott/default.nix
            {
              scott.gui = false;
              scott.standalone = true;
              scott.dotfiles.profile = profile;
            }
          ];
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
            nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen5
            ./hosts/eminix/configuration.nix
            disko.nixosModules.disko
            ./ioshi/hi-hardware/disko/eminix.nix
          ];
        };
      };

      # --- Standalone Home-Manager configurations (foreign distros) ---
      homeConfigurations = {
        "scott@datacore" = mkHome "server";
        "scott@work" = mkHome "wsl";
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
