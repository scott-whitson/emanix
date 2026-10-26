# The template is the ONLY thing a stranger's machine is built from, and one that
# does not evaluate fails on someone else's console with no context to debug it.
# So it is evaluated here, on every flake check, against fixture host.nix values.
#
# It deliberately does NOT go through the template's own flake.nix: that declares
# `emanix` as a github input, which the build sandbox cannot fetch. The modules are
# evaluated against THIS tree instead, which is the thing that drifts.
#
# Two deviations from a naive transcription of templates/default/flake.nix:
#
# 1. mkHost never includes disko.nixosModules.disko — the role checks never set
#    disko.devices, so they never needed it. The template's flake.nix adds it
#    explicitly, and this must too, or `disko.devices.disk.main` has no matching
#    option. Also in flake.nix's `lib` comment, where a consumer sees it.
#
# 2. checks/stub-hardware.nix defines fileSystems."/" at normal priority, which
#    collides with disko's real one here. Rather than change that shared fixture
#    for every other check, this supplies its own stub: the bootloader assertion.
#
# TWO fixtures, because `hardwareModule` has two code paths and Nix is lazy. The
# template appends `nixos-hardware.nixosModules.${host.hardwareModule}` only when
# the field is non-null; with a single null fixture that expression — the entire
# reason the nixos-hardware input exists — was never forced, so a typo in the
# attribute path would first surface on a stranger's console mid-install. The
# named module is `lenovo-thinkpad-t14-amd-gen5`, which exists upstream and is the
# one the fleet actually uses, so it is not a synthetic name that could quietly
# rot.
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
  mkTemplateHost = fixture:
    mkHost {
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
        (import ../modules/ewm.nix)
      ]
      ++ pkgs.lib.optional (fixture.hardwareModule != null)
        nixos-hardware.nixosModules.${fixture.hardwareModule};
    };

  drvFor = fixture:
    builtins.unsafeDiscardStringContext
      (mkTemplateHost fixture).config.system.build.toplevel.drvPath;

  # The composed Home Manager src options, so the assertions below can name
  # what a generated host actually carries. templateuser is the fixture
  # username, so these are the values for the template's own user.
  baseSrc = (mkTemplateHost baseFixture).config.home-manager.users.templateuser.emanix.src;
  show = v: if v == null then "null" else builtins.toString v;

  # The regression guard for a host built from the distribution alone. binDir
  # and dotfilesPath are null, and src.path under the template's liveElisp=false
  # is the repository as a store path — never a directory under $HOME that a
  # generated machine never created. If a $HOME default is reintroduced anywhere
  # on this axis, one of these throws.
  #
  # EVAL time, not inside the runCommand below: the gate that protects main is
  # `nix flake check --no-build`, which builds nothing, so an `exit 1` in a
  # build script can never fail it. Same idiom as checks/retired-names.nix and
  # checks/hardware-gpu.nix.
  srcProblems = [
    {
      ok = baseSrc.binDir == null;
      message = "emanix.src.binDir is ${show baseSrc.binDir}, not null; a host built from the distribution alone must not name a consumer bin/";
    }
    {
      ok = baseSrc.dotfilesPath == null;
      message = "emanix.src.dotfilesPath is ${show baseSrc.dotfilesPath}, not null; a host built from the distribution alone must not name a consumer checkout";
    }
    {
      # hasPrefix alone only proves "some store path". The config.el under it
      # is what proves this is the DISTRIBUTION's own tree.
      ok = pkgs.lib.hasPrefix "/nix/store/" baseSrc.path
        && builtins.pathExists (baseSrc.path + "/emacs/config.el");
      message = "emanix.src.path is ${show baseSrc.path}, not the distribution's own tree as a /nix/store path carrying emacs/config.el; under liveElisp=false it must be the repository as a store path, never a directory under the home that a generated host never created";
    }
  ];
  srcFailures = builtins.filter (p: !p.ok) srcProblems;

  nullDrv = drvFor baseFixture;
  # Same hostName, deliberately: the ONLY difference between the two fixtures
  # is the optional module, so the inequality asserted below can only be caused
  # by it.
  hardwareDrv = drvFor (baseFixture // {
    hardwareModule = "lenovo-thinkpad-t14-amd-gen5";
  });
in
if srcFailures != [ ] then
  throw
    ("template-host: a host built from the distribution alone is wrong.\n"
      + builtins.concatStringsSep "\n" (map (p: "  - ${p.message}") srcFailures))
else
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
