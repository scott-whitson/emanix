# mkHost — compose an emanix nixosSystem from a role, a user, and optional
# hardware + personal modules. The flake applies the first argument set (its
# inputs + shared modules); each host calls the result with
# { hostName, role, username, hardware ? null, extraModules ? [] }.
#
# `homeModules` are Home Manager modules for that user; `extraModules` are
# NixOS modules for the host. Both are optional. Use homeModules rather than
# reaching into home-manager.users.<username> from extraModules — mkHost
# already knows the username, and spelling it again is how the two drift.
#
# This is the DISTRIBUTION's composer: it knows nothing about any particular
# user's secrets, keys, or home-manager config. Personal modules (secrets,
# SSH keys, home-manager imports) arrive via `extraModules` from the consuming
# flake (e.g. dotfiles).
{ nixpkgs, home-manager, ewm, agenix, nixos-wsl, nixpkgsModule, mkHmModule, sharedSpecialArgs, system }:
{ hostName, role, username, hardware ? null, extraModules ? [ ], homeModules ? [ ] }:
# `role` no longer selects a profile — the roles are gone. emanix ships ONE
# shape; what a host IS (headless, laptop, WSL) is the consumer's to compose from
# extraModules. `role` survives purely as METADATA: it is set on
# home-manager.users.<u>.emanix.role below, exported as EMANIX_ROLE by zsh.nix,
# and branched on by consumers (dotfiles gates pi, claude and syncthing on it).
# A label the distro records and the consumer interprets — not a dispatch.
let
  # emanix.username is a NixOS-level option (declared in emanix.nix),
  # read by os-system/base.nix and i-intelligence/ewm.nix
  # to address home-manager.users.<username>. Set it from the mkHost argument.
  #
  # emanix.role is an HM-level option (declared in i-intelligence/theme.nix),
  # read by HM modules (e.g. zsh.nix). It is set inside the user's HM config.
  #
  # NOT mkDefault, unlike the HM wiring block. Those
  # carry the distribution's OPINIONS, which a consumer may outrank. These two
  # are the ARGUMENTS mkHost was called with: overriding `role` to something
  # other than the profile mkHost actually imported yields an incoherent host,
  # with the HM modules branching on one role while the NixOS tier composed
  # another. Role output is an opinion; mkHost input is an invariant.
  emanixCoreModule = {
    emanix.username = username;
    home-manager.users.${username}.emanix.role = role;
  };

  # homeModules — the seam for configuring the user mkHost already owns.
  # Without it every consumer host re-spells
  # `home-manager.users.<username>.…` inside extraModules, restating the name
  # they just passed as `username`. Modules listed here are spliced under it.
  homeModule = {
    home-manager.users.${username}.imports = homeModules;
  };
in
nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = sharedSpecialArgs // { inherit ewm nixos-wsl; };
  modules = [
    ../emanix.nix
    # mkDefault: NixOS-WSL needs to force this empty (setting the hostname at
    # activation breaks WSL's systemd user-session bootstrap, NixOS-WSL#888).
    { networking.hostName = nixpkgs.lib.mkDefault hostName; }
    emanixCoreModule
    homeModule
    nixpkgsModule
    agenix.nixosModules.default
    home-manager.nixosModules.home-manager
    (mkHmModule username)
  ]
  ++ nixpkgs.lib.optional (hardware != null) hardware
  ++ extraModules;
}
