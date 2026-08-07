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
          users.scott = {
            imports = [
              ./home/scott/default.nix
              catppuccin.homeManagerModules.catppuccin
            ];
            # eminix instances run the system-owned EWM Emacs. mkDefault so a
            # non-EWM NixOS host (whistle) can opt out while reusing hmModule.
            scott.ewm.enable = nixpkgs.lib.mkDefault true;
          };
        };
      };

      # Compose an eminix host: profile (os+i) + its hi layer.
      mkHost = import ./lib/mkHost.nix {
        inherit nixpkgs home-manager ewm agenix nixpkgsModule hmModule sharedSpecialArgs system;
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

        # NixOS-WSL on the work laptop — replaces the Debian WSL + scott@work
        # standalone HM pair at cutover (spec 2026-07-21; the host was named
        # weasel until 2026-08-04). Not an eminix instance (no EWM/hardware
        # layer), so composed here, not via mkHost.
        whistle = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = sharedSpecialArgs;
          modules = [
            nixos-wsl.nixosModules.default
            ./hosts/whistle/configuration.nix
            nixpkgsModule
            agenix.nixosModules.default
            home-manager.nixosModules.home-manager
            hmModule
            {
              home-manager.users.scott = {
                scott.dotfiles.profile = "wsl";
                scott.gui = false;
                scott.ewm.enable = false;
                # Real Linux terminal under WSLg (same flake-themed ghostty
                # as eminix) — gui stays false, this opts in surgically.
                scott.ghostty.enable = true;
                # Persistent ssh sessions from eminix land in zellij
                # (zellaude bar; config deployed live from base/zellij).
                scott.zellij.enable = true;
                # Shared network namespace with the Debian distro until it
                # retires: move this instance's syncthing off Debian's ports
                # (GUI 8384, sync 22000) or the two crash-collide.
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
        # Debian datacore (spec 2026-08-05-datacore-nixos-design.md). Not an
        # eminix instance (no EWM layer), so composed here, not via mkHost.
        # Hardware module shared with zord-old until zord-old is deleted
        # post-soak.
        datacore = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = sharedSpecialArgs;
          modules = [
            ./hosts/datacore/configuration.nix
            ./ioshi/hi-hardware/hp-15-ef2013dx.nix
            disko.nixosModules.disko
            ./ioshi/hi-hardware/disko/datacore.nix
            nixpkgsModule
            agenix.nixosModules.default
            home-manager.nixosModules.home-manager
            hmModule
            {
              home-manager.users.scott = {
                scott.gui = false;
                scott.dotfiles.profile = "server";
                # Headless, no EWM layer here — same reason whistle overrides
                # this back off. Without it, hmModule's mkDefault true would
                # leave standalone.nix's condition false and skip installing
                # any Emacs at all (the retiring standalone HM installed the
                # standalone pgtk build via this same option's default-false).
                scott.ewm.enable = false;
              };
            }
            # hp-15-ef2013dx.nix is shared with zord-old's LUKS+encrypted
            # install (its fileSystems/swapDevices/luks.devices are literal
            # /dev/mapper/cryptroot etc.). datacore is unencrypted by
            # decision (disko/datacore.nix) with its own layout on GPT
            # partlabels, so those disk-specific options conflict — force
            # datacore's own values here rather than edit the shared file
            # (must stay byte-identical so zord-old's drvPath is unchanged).
            {
              boot.initrd.luks.devices = nixpkgs.lib.mkForce { };
              fileSystems."/boot".device = nixpkgs.lib.mkForce "/dev/disk/by-partlabel/disk-main-boot";
              fileSystems."/".device = nixpkgs.lib.mkForce "/dev/disk/by-partlabel/disk-main-root";
              fileSystems."/nix".device = nixpkgs.lib.mkForce "/dev/disk/by-partlabel/disk-main-root";
              fileSystems."/home".device = nixpkgs.lib.mkForce "/dev/disk/by-partlabel/disk-main-root";
              swapDevices = nixpkgs.lib.mkForce [{ device = "/dev/disk/by-partlabel/disk-main-swap"; }];
            }
          ];
        };
      };

      # --- Disko configurations (declarative disk partitioning) ---
      diskoConfigurations = {
        eminix = import ./ioshi/hi-hardware/disko/eminix.nix;
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
