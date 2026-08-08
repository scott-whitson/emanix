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
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    catppuccin = {
      url = "github:catppuccin/nix";
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
    , catppuccin
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
          # Activation aborts rather than overwrite a file HM does not own. That
          # is the right default, but it means any pre-existing real file blocks
          # the whole switch (hit 2026-08-08 on rafik: programs.firefox wanted
          # ~/.mozilla/firefox/profiles.ini, which Firefox had already written).
          # With this set, HM renames the intruder to <file>.hm-bak and proceeds,
          # so a switch degrades to "one file moved" instead of "nothing applied".
          backupFileExtension = "hm-bak";
          users.scott = {
            imports = [
              ./home/scott/default.nix
              # homeModules, not the deprecated homeManagerModules — the old
              # name warns on every eval as of the 2026-08-08 catppuccin input.
              catppuccin.homeModules.catppuccin
            ];
            # eminix instances run the system-owned EWM Emacs. mkDefault so a
            # non-EWM NixOS host (whistle) can opt out while reusing hmModule.
            scott.ewm.enable = nixpkgs.lib.mkDefault true;
          };
        };
      };

      # Compose an eminix host: profile (os+i) + its hi layer.
      mkHost = import ./lib/mkHost.nix {
        inherit nixpkgs home-manager ewm agenix nixos-wsl nixpkgsModule hmModule sharedSpecialArgs system;
      };

    in
    {
      # --- NixOS configurations — eminix instances ---
      nixosConfigurations = {
        # ThinkPad T14 Gen 5 AMD — daily driver (the eminix platform)
        rafik = mkHost {
          hostName = "rafik";
          role = "workstation";
          hardware = ./ioshi/hi-hardware/lenovo-t14-gen5-amd.nix;
          extraModules = [
            nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen5
            ./hosts/rafik/configuration.nix
            disko.nixosModules.disko
            ./ioshi/hi-hardware/disko/rafik.nix
          ];
        };

        # NixOS-WSL on the work laptop — replaces the Debian WSL + scott@work
        # standalone HM pair at cutover (spec 2026-07-21; the host was named
        # weasel until 2026-08-04).
        whistle = mkHost {
          hostName = "whistle";
          role = "wsl";
          extraModules = [
            ./hosts/whistle/configuration.nix
            {
              # Syncthing ports moved off the defaults during Debian
              # cohabitation. Debian retired 2026-08-04 — see Step 6.
              home-manager.users.scott = {
                services.syncthing.guiAddress = "127.0.0.1:8385";
                services.syncthing.settings.options.listenAddresses = [
                  "tcp://0.0.0.0:22001"
                  "quic://0.0.0.0:22001"
                ];
              };
            }
          ];
        };

        # Headless home server on the HP freed by zord's T14 move — replaces
        # Debian datacore (spec 2026-08-05-datacore-nixos-design.md).
        datacore = mkHost {
          hostName = "datacore";
          role = "server";
          hardware = ./ioshi/hi-hardware/hp-15-ef2013dx.nix;
          extraModules = [
            ./hosts/datacore/configuration.nix
            disko.nixosModules.disko
            ./ioshi/hi-hardware/disko/datacore.nix
          ];
        };
      };

      # --- Disko configurations (declarative disk partitioning) ---
      diskoConfigurations = {
        rafik = import ./ioshi/hi-hardware/disko/rafik.nix;
        datacore = import ./ioshi/hi-hardware/disko/datacore.nix;
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
