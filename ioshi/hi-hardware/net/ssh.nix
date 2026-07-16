{ ... }:
{
  # SSH — remote administration (key-based) from datacore or swhitson-11l.
  services.openssh.enable = true;
  users.users.scott.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHeRiEMkgSu+cBXTs7ekkJdT5JzJYCfDadrpFgDFn560 scott@datacore"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINW1gKUfmcHDWf02SHUpZuIZEqq7qk4IJfmd8hlLAUQi swhitson-11l"
  ];
}
