# emanix.hardware.gpu drives boot.initrd.kernelModules, and the failure mode
# when it is wrong is a black screen on a machine with no other console. So
# each value is asserted here rather than trusted to review.
#
# Note kernelModules, NOT availableKernelModules: nixos-generate-config writes
# the latter (modules PERMITTED in the initrd) and never the former (modules
# FORCED to load). EWM needs the forced form, which is the whole reason this
# option exists — see modules/gpu.nix.
#
# The same file also holds the assertion that couples the option to firmware: a
# gpu value with hardware.enableRedistributableFirmware = false must fail
# evaluation, because boot.initrd.allowMissingModules would otherwise turn the
# missing firmware into a build-log line.
{ pkgs, mkHost, ... }:
let
  hostWith = extra: mkHost {
    hostName = "checkhost";
    role = "workstation";
    username = "checkuser";
    hardware = ./stub-hardware.nix;
    extraModules = [ extra ];
    homeModules = [{ }];
  };

  initrdModulesFor = gpu:
    (hostWith { emanix.hardware.gpu = gpu; }).config.boot.initrd.kernelModules;

  # Whether the host's toplevel evaluates. builtins.tryEval catches the throw
  # NixOS raises for a failed assertion; nothing is built.
  evaluates = extra:
    (builtins.tryEval (builtins.unsafeDiscardStringContext
      (hostWith extra).config.system.build.toplevel.drvPath)).success;

  amd = initrdModulesFor "amd";
  intel = initrdModulesFor "intel";
  none = initrdModulesFor null;

  has = m: xs: builtins.elem m xs;

  results = [
    { name = "amd-loads-amdgpu"; ok = has "amdgpu" amd; }
    { name = "amd-omits-i915"; ok = !(has "i915" amd); }
    { name = "intel-loads-i915"; ok = has "i915" intel; }
    { name = "intel-omits-amdgpu"; ok = !(has "amdgpu" intel); }
    { name = "null-loads-neither"; ok = !(has "amdgpu" none) && !(has "i915" none); }
    # Positive control for the next case: without it, "is rejected" would also
    # pass if the host simply never evaluated.
    {
      name = "amd-with-firmware-evaluates";
      ok = evaluates { emanix.hardware.gpu = "amd"; };
    }
    {
      name = "amd-without-firmware-is-rejected";
      ok = !(evaluates {
        emanix.hardware.gpu = "amd";
        hardware.enableRedistributableFirmware = false;
      });
    }
    {
      name = "no-gpu-without-firmware-evaluates";
      ok = evaluates { hardware.enableRedistributableFirmware = false; };
    }
  ];

  failures = builtins.filter (r: !r.ok) results;
in
if failures == [ ] then
  pkgs.runCommand "emanix-hardware-gpu" { } "echo ok > $out"
else
  throw ("emanix.hardware.gpu is wired wrong: "
    + builtins.concatStringsSep ", " (map (r: r.name) failures))
