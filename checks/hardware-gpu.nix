# emanix.hardware.gpu drives boot.initrd.kernelModules, and the failure mode
# when it is wrong is a black screen on a machine with no other console. So
# each value is asserted here rather than trusted to review.
#
# Note kernelModules, NOT availableKernelModules: nixos-generate-config writes
# the latter (modules PERMITTED in the initrd) and never the former (modules
# FORCED to load). EWM needs the forced form, which is the whole reason this
# option exists — see ioshi/hi-hardware/gpu.nix.
{ pkgs, mkHost, ... }:
let
  initrdModulesFor = gpu:
    (mkHost {
      hostName = "checkhost";
      role = "workstation";
      username = "checkuser";
      hardware = ./stub-hardware.nix;
      extraModules = [{ emanix.hardware.gpu = gpu; }];
      homeModules = [{ }];
    }).config.boot.initrd.kernelModules;

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
  ];

  failures = builtins.filter (r: !r.ok) results;
in
if failures == [ ] then
  pkgs.runCommand "emanix-hardware-gpu" { } "echo ok > $out"
else
  throw ("emanix.hardware.gpu is wired wrong: "
    + builtins.concatStringsSep ", " (map (r: r.name) failures))
