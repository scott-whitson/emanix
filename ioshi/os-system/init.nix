{ pkgs, ... }:
{
  # `emanix-init` on PATH for every host. Unlike emanix-firstboot, the
  # distribution owns this one's CONTENT: adopting a generated config into a
  # repo is the same operation on every machine, and it names no
  # infrastructure.
  #
  # writeShellApplication rather than a repo bin/ script, matching
  # firstboot.nix: the body is shellchecked at build time, so a broken
  # emanix-init fails the build rather than failing on a stranger's console.
  config.environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "emanix-init";
      runtimeInputs = with pkgs; [ git nix ];
      text = builtins.readFile ../../installer/emanix-init.sh;
    })
  ];
}
