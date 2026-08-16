{
  description = "eminix — a NixOS distribution (Emacs + Linux + NixOS)";

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
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
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
    , nixos-wsl
    , ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      eminixLib = import ./lib;
      sharedSpecialArgs = { inherit eminixLib; };

      # Applied to all NixOS systems; Home Manager inherits it via
      # useGlobalPkgs.
      nixpkgsModule = {
        nixpkgs.overlays = [ emacs-overlay.overlays.default ];
        nixpkgs.config.allowUnfree = true;
        nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];
      };

      # Home Manager wiring: import the eminix HM modules for the given user.
      # The consuming flake adds personal home config via extraModules.
      mkHmModule = username: {
        home-manager = {
          extraSpecialArgs = sharedSpecialArgs;
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "hm-bak";
          users.${username} = {
            imports = [ ./ioshi/i-intelligence ];
            # The distribution tracks nixpkgs unstable; consumers pin their own
            # stateVersion in personal config if they need a different one.
            home.stateVersion = "26.05";
          };
        };
      };

      # Compose an eminix host: core + role + user + hardware + personal extras.
      mkHost = import ./lib/mkHost.nix {
        inherit nixpkgs home-manager ewm agenix nixos-wsl nixpkgsModule sharedSpecialArgs system;
        mkHmModule = mkHmModule;
      };

    in
    {
      # NixOS modules exported for consuming flakes (dotfiles, other hosts).
      nixosModules = {
        default = import ./profiles/eminix.nix;
        eminix = import ./profiles/eminix.nix;
        roles = {
          workstation = import ./profiles/roles/workstation.nix;
          server = import ./profiles/roles/server.nix;
          wsl = import ./profiles/roles/wsl.nix;
        };
      };

      # The host composer, parameterized: { hostName, role, username, hardware, extraModules }
      lib = { inherit mkHost; };

      # The installer ISO — a tool, not an eminix host.
      nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit nixpkgs disko; };
        modules = [ ./installer/iso.nix ];
      };

      # The installer ISO as a package (nix build .#installerIso).
      packages.${system}.installerIso =
        self.nixosConfigurations.installer.config.system.build.isoImage;

      # Disko configurations are defined by consumers (per-host disk layouts
      # are personal). The installer carries the disko INPUT so consuming
      # flakes can build their own.

      # Builder dev shell.
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