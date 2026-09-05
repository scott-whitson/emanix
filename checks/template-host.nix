# The template is the ONLY thing a stranger's machine is built from, and a
# template that does not evaluate produces a failure on someone else's console
# with no context to debug it. So it is evaluated here, on every flake check,
# against a fixture host.nix.
#
# It deliberately does NOT go through the template's own flake.nix: that
# declares `emanix` as a github input, which the build sandbox cannot fetch.
# The modules are evaluated against THIS tree instead, which is the thing that
# actually drifts.
# NOTE (deviations required to make this evaluate, from what a naive
# transcription of templates/default/flake.nix's module list would do):
#
# 1. mkHost's own module list never includes disko.nixosModules.disko — the
#    distro's role checks never set disko.devices, so they never needed it.
#    The template's OWN flake.nix adds it explicitly alongside disko.nix (see
#    templates/default/flake.nix), and this check must do the same or
#    disko.nix's `disko.devices.disk.main` definition has no matching option.
#
# 2. checks/stub-hardware.nix defines fileSystems."/" (for the role checks,
#    which never touch disko) at normal priority, which collides with the
#    real fileSystems."/" disko.nix's module produces here. Rather than
#    change that shared fixture's priority for every other check, this check
#    supplies its own minimal hardware stub with only what disko does not
#    already cover: the bootloader assertion. fileSystems."/" comes from
#    disko; system.stateVersion comes from configuration.nix.
{ pkgs, mkHost, disko, ... }:
let
  fixture = {
    hostName = "templatehost";
    device = "/dev/vda";
    luks = false;
    filesystem = "btrfs";
    swapSize = "0";
    gpu = "amd";
    hardwareModule = null;
  };
in
pkgs.runCommand "emanix-template-host" { } ''
  echo ${
    builtins.unsafeDiscardStringContext
      (mkHost {
        hostName = fixture.hostName;
        role = "workstation";
        username = "templateuser";
        # Not ../checks/stub-hardware.nix — see the NOTE above.
        hardware = { boot.loader.grub.enable = false; };
        extraModules = [
          disko.nixosModules.disko
          (import ../lib/disk.nix {
            inherit (fixture) device luks filesystem swapSize;
          })
          { emanix.hardware.gpu = fixture.gpu; }
          (import ../templates/default/configuration.nix)
          # The template's OWN flake.nix includes this too (as
          # emanix.nixosModules.ewm) -- omitting it here would mean this
          # check exercises a smaller module set than the template actually
          # ships, and never evaluates the compositor a real generated host
          # gets. `ewm` (the flake input) reaches this module via mkHost's
          # own specialArgs, same as every other consumer of
          # emanix.nixosModules.ewm.
          (import ../ioshi/i-intelligence/ewm.nix)
        ];
        homeModules = [{ }];
      }).config.system.build.toplevel.drvPath
  } > $out
''
