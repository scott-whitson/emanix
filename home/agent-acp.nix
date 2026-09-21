# The ACP adapters that agent-shell drives to reach Claude Code and pi.
#
# No `emanix.*' option: these are four small scripts, and the elisp guards on
# each binary's presence, so a host with no Claude subscription -- or no pi --
# loses a keybinding rather than failing to build. Same shape as the guard that
# used to wrap the claude-code-ide checkout.
#
# The pi pair ships even though pi itself lives in the PERSONAL layer
# (dotfiles/home/scott/default.nix installs pi-coding-agent, because which AI
# harness to run is a personal choice). That is deliberate and costs nothing: a
# wrapper is a few hundred bytes, it refuses to run when `pi' is absent and
# says why, and the alternative -- emanix pinning pi's store path -- would make
# the distribution depend on one consumer's taste in agents.
{ pkgs, ... }:
let
  wrappers = import ../agent-acp/wrappers.nix { inherit pkgs; };
in
{
  home.packages = [
    wrappers.adapter
    wrappers.updater
    wrappers.piAdapter
    wrappers.piUpdater
  ];
}
