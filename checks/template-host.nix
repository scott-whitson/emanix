# The template is the ONLY thing a stranger's machine is built from, and a
# template that does not evaluate produces a failure on someone else's console
# with no context to debug it. So it is evaluated here, on every flake check,
# against fixture host.nix values.
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
#    This is also written down in flake.nix's `lib` comment, where a consumer
#    reading mkDisk's signature will actually see it.
#
# 2. checks/stub-hardware.nix defines fileSystems."/" (for the role checks,
#    which never touch disko) at normal priority, which collides with the
#    real fileSystems."/" disko.nix's module produces here. Rather than
#    change that shared fixture's priority for every other check, this check
#    supplies its own minimal hardware stub with only what disko does not
#    already cover: the bootloader assertion. fileSystems."/" comes from
#    disko; system.stateVersion comes from configuration.nix.
#
# TWO fixtures, because `hardwareModule` has two code paths and Nix is lazy.
# The template appends `nixos-hardware.nixosModules.${host.hardwareModule}`
# only when the field is non-null; with a single null fixture that expression
# — the entire reason the nixos-hardware input exists — was never forced by
# any check, so a typo in the attribute path or a vanished upstream module
# would first surface on a stranger's console mid-install. The named module is
# `lenovo-thinkpad-t14-amd-gen5`: it exists upstream and is the one the fleet
# actually uses, so this is not a synthetic name that could quietly rot.
{ pkgs, mkHost, disko, nixos-hardware, ... }:
let
  baseFixture = {
    hostName = "templatehost";
    device = "/dev/vda";
    luks = false;
    filesystem = "btrfs";
    swapSize = "0";
    gpu = "amd";
    hardwareModule = null;
  };

  # Transcribes templates/default/flake.nix's module list, including the
  # optional tail. Keep the two in step: this check is only worth anything
  # while it composes what the template composes.
  drvFor = fixture:
    builtins.unsafeDiscardStringContext
      (mkHost {
        inherit (fixture) hostName;
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
        ]
        ++ pkgs.lib.optional (fixture.hardwareModule != null)
          nixos-hardware.nixosModules.${fixture.hardwareModule};
      }).config.system.build.toplevel.drvPath;

  nullDrv = drvFor baseFixture;
  # Same hostName, deliberately: the ONLY difference between the two fixtures
  # is the optional module, so the inequality asserted below can only be caused
  # by it.
  hardwareDrv = drvFor (baseFixture // {
    hardwareModule = "lenovo-thinkpad-t14-amd-gen5";
  });
in
pkgs.runCommand "emanix-template-host" { } ''
  echo ${nullDrv} > $out
  echo ${hardwareDrv} >> $out

  # A per-model module that contributed nothing would make this check a
  # tautology: both fixtures would evaluate, both would produce the same
  # system, and the hardwareModule path would still be untested in substance.
  ${pkgs.lib.optionalString (nullDrv == hardwareDrv) ''
    echo "template-host: the nixos-hardware fixture produced an identical system to the null one; the hardwareModule path is contributing nothing" >&2
    exit 1
  ''}
''
