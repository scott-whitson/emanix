# mkHost — compose an eminix nixosSystem from a role and an optional hi layer.
# The flake applies the first argument set (its inputs + shared modules); each
# host calls the result with { hostName, role, hardware ? null, extraModules ? [] }.
{ nixpkgs, home-manager, ewm, agenix, nixos-wsl, nixpkgsModule, hmModule, sharedSpecialArgs, system }:
{ hostName, role, hardware ? null, extraModules ? [ ] }:
nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = sharedSpecialArgs // { inherit ewm nixos-wsl; };
  modules = [
    ../profiles/eminix.nix
    ../profiles/roles/${role}.nix
    # mkDefault: whistle must force this empty — NixOS setting the hostname at
    # activation breaks WSL's systemd user-session bootstrap (NixOS-WSL#888).
    { networking.hostName = nixpkgs.lib.mkDefault hostName; }
    # scott.role comes from the same argument that selected the role profile
    # above, so the option and the imported profile cannot disagree. Modules
    # that need to branch on host shape read this rather than re-deriving it.
    { home-manager.users.scott.scott.role = role; }
    nixpkgsModule
    agenix.nixosModules.default
    home-manager.nixosModules.home-manager
    hmModule
  ]
  ++ nixpkgs.lib.optional (hardware != null) hardware
  ++ extraModules;
}
