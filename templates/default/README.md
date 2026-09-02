# An emanix host

The machine-specific parts of this repo are `host.nix` and the `username` set
in `flake.nix`. Everything else reads from those.

If `fresh-emanix-install` generated this repo for you, both are already set —
skip straight to the rebuild command below. If you started from
`nix flake init -t github:scott-whitson/emanix`, set `username` in
`flake.nix` yourself before rebuilding.

Before the first rebuild, generate a hardware module:

    sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix

Then rebuild:

    sudo nixos-rebuild switch --flake .#$(nix eval --raw -f host.nix hostName)

Documentation: https://emanix.net
