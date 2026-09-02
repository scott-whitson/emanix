# An emanix host

`host.nix` is the only file describing this machine. Everything else reads
from it.

Before the first rebuild, generate a hardware module:

    sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix

Then set `username` in `flake.nix` and rebuild:

    sudo nixos-rebuild switch --flake .#$(nix eval --raw -f host.nix hostName)

Documentation: https://emanix.net
