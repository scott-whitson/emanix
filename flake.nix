{
  description = "emanix — a NixOS distribution (Emacs + Linux + NixOS)";

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
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The machine database — over 400 per-model modules. Carried by the
    # DISTRIBUTION rather than by each consumer: which tuning a ThinkPad needs
    # is not a personal fact, and a consumer that has to add this input itself
    # cannot use the template's `hardwareModule` field at all.
    #
    # Deliberately NOT auto-selected. nixos-hardware ships no DMI machinery and
    # its names are not a convention (lenovo-thinkpad-t14-amd-gen5 vs
    # framework-13-7040-amd vs hp-laptop-15s-fq1xxx); a prototype matcher
    # resolved 2 of 6 realistic machines. Hardware discovery is
    # nixos-generate-config. See the spec's "Why there is no hardware
    # auto-detection".
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
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

      emanixLib = import ./lib;
      sharedSpecialArgs = { inherit emanixLib; };

      # Applied to all NixOS systems; Home Manager inherits it via
      # useGlobalPkgs.
      nixpkgsModule = {
        nixpkgs = {
          overlays = [ emacs-overlay.overlays.default ];
          config.allowUnfree = true;
          config.permittedInsecurePackages = [ "electron-39.8.10" ];
        };
      };

      # Home Manager wiring: import the emanix HM modules for the given user.
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

      # Compose an emanix host: core + role + user + hardware + personal extras.
      mkHost = import ./lib/mkHost.nix {
        inherit nixpkgs home-manager ewm agenix nixos-wsl nixpkgsModule sharedSpecialArgs system;
        inherit mkHmModule;
      };

    in
    {
      # NixOS modules exported for consuming flakes (dotfiles, other hosts).
      nixosModules = {
        default = import ./emanix.nix;
        emanix = import ./emanix.nix;
        # No `roles` output any more. emanix is ONE shape; a consumer composes
        # the rest. What is offered instead is the compositor as a named
        # module, so a host that wants a graphical session imports it
        # explicitly rather than inheriting it from a role it did not choose.
        ewm = import ./ioshi/i-intelligence/ewm.nix;
        installer = import ./installer/iso.nix;
      };

      templates.default = {
        path = ./templates/default;
        description = "An emanix host: one host.nix, a parameterized disk layout, and the distribution";
      };

      # The host composer and the disk layout, both parameterized.
      # mkHost:  { hostName, role, username, hardware, extraModules, homeModules }
      # mkDisk:  { device, luks, filesystem, swapSize, extraSubvolumes }
      #
      # mkDisk is the distro's opinion about disk SHAPE; the consumer still
      # supplies the device and the options, so "disko configurations are
      # defined by consumers" holds — they just stop retyping the layout.
      lib = { inherit mkHost; mkDisk = import ./lib/disk.nix; };

      # A generic installer ISO — stages the distro flake, no keys. The
      # distro ships a DEBUG/rescue ISO; real installs are built by consuming
      # flakes (dotfiles) via nixosModules.installer with
      # emanix.installer.{flake,keysDir} set.
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
            pkgs.runCommand "emanix-eval-${role}" { } ''
              echo ${
                builtins.unsafeDiscardStringContext
                  (mkHost {
                    hostName = "checkhost";
                    inherit role;
                    username = "checkuser";
                    hardware = ./checks/stub-hardware.nix;
                    # A do-nothing consumer module, so the homeModules seam is
                    # evaluated rather than merely accepted.
                    homeModules = [{ }];
                  }).config.system.build.toplevel.drvPath
              } > $out
            '';

          # tests/contrast-check.py is a pure function of palette data (no
          # Emacs, no temp trees, no subprocess timeouts like init-guard.sh),
          # so it costs nothing to run on every `nix flake check`. The script
          # reads palettes as JSON on stdin, so the palettes are serialized at
          # build time and piped in.
          palettesJson = pkgs.writeText "emanix-palettes.json"
            (builtins.toJSON (emanixLib.theme { inherit pkgs; }).palettes);
        in
        {
          role-workstation = evalRole "workstation";
          role-server = evalRole "server";
          # Also exercises the homeModules seam, so it cannot silently break.
          role-wsl = evalRole "wsl";

          # The arc glue's paths, checked on every flake check rather than
          # whenever someone remembers to look. See checks/arc-glue.nix.
          arc-glue = import ./checks/arc-glue.nix { inherit pkgs; };

          palette-contrast = pkgs.runCommand "emanix-palette-contrast" { } ''
            ${pkgs.python3}/bin/python3 ${./tests/contrast-check.py} < ${palettesJson} > $out
          '';

          # The template a stranger's machine is built from, evaluated on every
          # flake check. See checks/template-host.nix.
          template-host = import ./checks/template-host.nix { inherit pkgs mkHost disko; };

          # emanix.hardware.gpu's effect on the initrd, checked per value.
          # See checks/hardware-gpu.nix.
          hardware-gpu = import ./checks/hardware-gpu.nix { inherit pkgs mkHost; };

          # The welcome buffer's claims, checked against the bindings that
          # back them. See checks/welcome-keys.nix.
          welcome-keys = import ./checks/welcome-keys.nix { inherit pkgs; };
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
