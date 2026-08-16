# mkHost — compose an eminix nixosSystem from a role, a user, and optional
# hardware + personal modules. The flake applies the first argument set (its
# inputs + shared modules); each host calls the result with
# { hostName, role, username, hardware ? null, extraModules ? [] }.
#
# This is the DISTRIBUTION's composer: it knows nothing about any particular
# user's secrets, keys, or home-manager config. Personal modules (secrets,
# SSH keys, home-manager imports) arrive via `extraModules` from the consuming
# flake (e.g. dotfiles).
{ nixpkgs, home-manager, ewm, agenix, nixos-wsl, nixpkgsModule, mkHmModule, sharedSpecialArgs, system }:
{ hostName, role, username, hardware ? null, extraModules ? [ ] }:
let
  # eminix.username is a NixOS-level option (declared in profiles/eminix.nix),
  # read by os-system/base.nix, i-intelligence/ewm.nix, and the role profiles
  # to address home-manager.users.<username>. Set it from the mkHost argument.
  #
  # eminix.role is an HM-level option (declared in i-intelligence/theme.nix),
  # read by HM modules (e.g. zsh.nix). It is set inside the user's HM config.
  eminixCoreModule = {
    eminix.username = username;
    home-manager.users.${username}.eminix.role = role;
  };
in
nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = sharedSpecialArgs // { inherit ewm nixos-wsl; };
  modules = [
    ../profiles/eminix.nix
    ../profiles/roles/${role}.nix
    # mkDefault: NixOS-WSL needs to force this empty (setting the hostname at
    # activation breaks WSL's systemd user-session bootstrap, NixOS-WSL#888).
    { networking.hostName = nixpkgs.lib.mkDefault hostName; }
    eminixCoreModule
    nixpkgsModule
    agenix.nixosModules.default
    home-manager.nixosModules.home-manager
    (mkHmModule username)
  ]
  ++ nixpkgs.lib.optional (hardware != null) hardware
  ++ extraModules;
}
