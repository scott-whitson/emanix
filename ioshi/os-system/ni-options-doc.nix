{ config, lib, pkgs, ... }:
let
  # Render THIS machine's declared NixOS options to markdown so ni can retrieve
  # correct option names/types/defaults instead of hallucinating them. Sourced
  # from the manual's optionsJSON (built anyway for the system manual).
  optionsMd = pkgs.runCommand "ni-nixos-options.md" { } ''
    ${pkgs.jq}/bin/jq -r '
      to_entries[]
      | "## \(.key)\n\nType: \(.value.type // "n/a")\nDefault: \(.value.default.text // "n/a")\n\n\(.value.description // "")\n"
    ' ${config.system.build.manual.optionsJSON}/share/doc/nixos/options.json > $out
  '';
in {
  environment.etc."ni/nixos-options.md".source = optionsMd;
}
