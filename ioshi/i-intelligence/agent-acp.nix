# The ACP adapter that agent-shell drives to reach Claude Code.
#
# No `emanix.*' option: these are two small scripts, and the elisp guards on
# the binary's presence, so a host with no Claude subscription loses a
# keybinding rather than failing to build -- the same shape as the guard that
# used to wrap the claude-code-ide checkout.
{ pkgs, ... }:
let
  wrappers = import ./agent-acp/wrappers.nix { inherit pkgs; };
in
{
  home.packages = [ wrappers.adapter wrappers.updater ];
}
