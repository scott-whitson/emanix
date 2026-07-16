{ pkgs, ... }:
{
  # One-time post-install helper, on PATH after boot (source: installer/eminix-firstboot).
  # writeShellApplication shellchecks it at build time, so a broken script fails the build.
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "eminix-firstboot";
      runtimeInputs = with pkgs; [ tailscale syncthing git ];
      text = builtins.readFile ../../installer/eminix-firstboot;
    })
  ];
}
