{ lib, pkgs, config, ... }:
let
  cfg = config.eminix.firstboot;
in
{
  # A one-time post-install helper on PATH, by convention named
  # `eminix-firstboot`. The distribution owns the CONVENTION and the build-time
  # check; it owns none of the content.
  #
  # It used to ship a script whose entire body was "join a tailnet against a
  # self-hosted headscale" — 69 lines of one deployment's topology, in a
  # distribution. Its own closing lines admitted as much, telling the reader
  # that personal setup belongs to the consuming flake. So the content moved
  # there and this became the seam it should always have been.
  #
  # writeShellApplication shellchecks at build time, so a consumer's broken
  # first-boot script fails the build rather than the first boot — which is the
  # one moment nobody is watching a screen they can debug from.
  options.eminix.firstboot = {
    text = lib.mkOption {
      type = lib.types.lines;
      default = ''
        printf '\n==> eminix first-boot\n'
        printf 'No first-boot steps are configured.\n'
        printf 'Set eminix.firstboot.text in your consuming flake.\n'
      '';
      description = ''
        Body of the `eminix-firstboot` command. The default is a stub that says
        so: a distribution cannot know what your first boot needs — a tailnet to
        join, a config repo to clone, secrets to place — and guessing produces a
        script that is wrong for everyone but its author.
      '';
    };

    runtimeInputs = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.tailscale pkgs.git ]";
      description = ''
        Packages on PATH for the script. Empty by default — the previous version
        listed tailscale, syncthing and git while the script used only tailscale,
        which is the kind of drift an unused input never announces.
      '';
    };
  };

  config.environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "eminix-firstboot";
      inherit (cfg) runtimeInputs text;
    })
  ];
}
