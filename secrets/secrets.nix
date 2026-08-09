let
  # Recipients. Hosts decrypt with their SSH host key; scott edits with
  # ~/.ssh/id_ed25519 (swhitson-11l). rafik's key is pre-generated (its private
  # half must be injected at /etc/ssh/ssh_host_ed25519_key during install).
  # Key comment still reads root@eminix: the host was renamed to rafik on
  # 2026-08-07 but its SSH host key was NOT regenerated, so this string must
  # stay verbatim. Same situation as whistle (renamed from weasel 2026-08-04).
  rafik = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHiZAqCjE7nX2iXAlZDdZIzURl/X55ljlbpVHNlN9Za8 root@eminix";
  zordold = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBp0MtitZy/niGsNtI2BzKER7UtKT6R9+wMhrS/X2pdB root@zord-old";
  # datacore inherits the OLD Debian box's SSH host key at cutover (spec
  # decision 8): /etc/ssh/ssh_host_* are copied so peers never re-pin. The
  # agenix recipient must therefore BE that key — a host cannot inherit one
  # key and decrypt with another. A freshly generated key was briefly used
  # here on 2026-08-08 and was wrong for exactly that reason.
  datacore = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHn7dUeQQeGMDAuQ8YJRxV2Nlo31biEtxpcHxawrBZ1J root@datacore";
  # Key comment still reads root@weasel: the host was renamed 2026-08-04 but
  # its SSH host key was NOT regenerated, so this string must stay verbatim.
  whistle = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINp8VpIPlKLxcfPh1jvPc+LnFOnyQhTyxMulwQbTg2xA root@weasel";
  scott = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINW1gKUfmcHDWf02SHUpZuIZEqq7qk4IJfmd8hlLAUQi swhitson-11l";
in
{
  "openrouter-auth.age".publicKeys = [ rafik datacore zordold whistle scott ];
  "ibkr-creds.age".publicKeys = [ rafik scott ];
}
