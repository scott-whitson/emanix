# mkHost — compose an eminix nixosSystem from a role and an optional hi layer.
# The flake applies the first argument set (its inputs + shared modules); each
# host calls the result with { hostName, role, hardware ? null, extraModules ? [] }.
{ nixpkgs, home-manager, ewm, agenix, agenix-rekey, nixos-wsl, nixpkgsModule, hmModule, sharedSpecialArgs, system }:
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
    agenix-rekey.nixosModules.default
    # agenix-rekey: secrets live master-key-encrypted under secrets/, and are
    # rekeyed per host into secrets/rekeyed/<host>/ at build time. hostPubkey
    # MUST be the committed keys/<host>_host_ed25519.pub path — every host
    # evaluates on the builder (rafik), where /etc/ssh/... is the BUILDER's own
    # key, so a /etc path would rekey every host for rafik.
    {
      age.rekey = {
        masterIdentities = [ "/home/scott/.ssh/id_ed25519" ];
        storageMode = "local";
        localStorageDir = "${../.}/secrets/rekeyed/${hostName}";
        hostPubkey = ../keys + "/${hostName}_host_ed25519.pub";
      };
    }
    home-manager.nixosModules.home-manager
    hmModule
  ]
  ++ nixpkgs.lib.optional (hardware != null) hardware
  ++ extraModules;
}
