{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = [
    (pkgs.python312.withPackages (ps: with ps; [
      google-api-python-client
      google-auth
      google-auth-oauthlib
      python-dateutil
    ]))
  ];
}