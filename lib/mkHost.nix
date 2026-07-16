# mkHost — compose an eminix nixosSystem from a host's hi selection.
# The flake applies the first argument set (its inputs + shared modules); each
# host calls the result with { hostName, hardware, extraModules ? [] }.
{ nixpkgs, home-manager, ewm, agenix, nixpkgsModule, hmModule, sharedSpecialArgs, system }:
{ hostName, hardware, extraModules ? [ ] }:
nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = sharedSpecialArgs // { inherit ewm; };
  modules = [
    ../profiles/eminix.nix
    hardware
    { networking.hostName = hostName; }
    nixpkgsModule
    agenix.nixosModules.default
    home-manager.nixosModules.home-manager
    hmModule
  ] ++ extraModules;
}
