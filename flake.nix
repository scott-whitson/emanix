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
      # mkDefault throughout, for the same reason as the role profiles: these
      # are the distribution's opinions about how to wire Home Manager, not
      # invariants. Until they were mkDefault the comment below was a lie —
      # a consumer taking it up got "conflicting definition values" instead of
      # their own stateVersion.
      mkHmModule = username: {
        home-manager = {
          extraSpecialArgs = sharedSpecialArgs;
          useGlobalPkgs = nixpkgs.lib.mkDefault true;
          useUserPackages = nixpkgs.lib.mkDefault true;
          # Consumers who would rather HM refuse than move a file aside can
          # set this to null. Note it is what renames a clobbered file to
          # <name>.hm-bak, which lands IN a checkout when the target is an
          # out-of-store symlink into one.
          backupFileExtension = nixpkgs.lib.mkDefault "hm-bak";
          users.${username} = {
            imports = [ ./ioshi/i-intelligence ];
            # The distribution tracks nixpkgs unstable; consumers pin their own
            # stateVersion in personal config if they need a different one.
            home.stateVersion = nixpkgs.lib.mkDefault "26.05";
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
        installer = import ./installer/iso.nix;
      };

      # The host composer, parameterized: { hostName, role, username, hardware, extraModules }
      lib = { inherit mkHost; };

      # A generic installer ISO — stages the distro flake, no keys. The
      # distro ships a DEBUG/rescue ISO; real installs are built by consuming
      # flakes (dotfiles) via nixosModules.installer with
      # eminix.installer.{flake,keysDir} set.
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

      # Evaluation checks — the distro validating ITSELF.
      #
      # nix flake check otherwise touches almost nothing here: it does not
      # reach lib.mkHost, the role profiles, or any of the Home Manager
      # modules under ioshi/i-intelligence/, so a broken option or a renamed
      # upstream setting stays green until a CONSUMER's rebuild trips over
      # it. Each check below composes a throwaway host through the real
      # mkHost and forces its toplevel, which drags in the role profile, the
      # NixOS tier, every HM module and NixOS's own assertions.
      #
      # EVALUATED, NEVER BUILT. unsafeDiscardStringContext drops the
      # derivation dependency, so the drvPath is computed (that is the whole
      # point) but no closure is realized. Deliberate: the workstation role
      # pulls EWM, whose closure source-compiles and can take down a WSL host
      # — a check that cannot be run safely on the machine you have is not a
      # check.
      #
      # The username is intentionally NOT the author's. Any module that
      # hardcodes a real one fails here rather than in a stranger's rebuild.
      checks.${system} =
        let
          evalRole = role:
            pkgs.runCommand "eminix-eval-${role}" { } ''
              echo ${
                builtins.unsafeDiscardStringContext
                  (mkHost {
                    hostName = "checkhost";
                    inherit role;
                    username = "checkuser";
                    hardware = ./checks/stub-hardware.nix;
                  }).config.system.build.toplevel.drvPath
              } > $out
            '';
        in
        {
          role-workstation = evalRole "workstation";
          role-server = evalRole "server";
          role-wsl = evalRole "wsl";
        };

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
