# An emanix host

The machine-specific parts of this repo are `host.nix` and the `username` set
in `flake.nix`. Everything else reads from those.

If `fresh-emanix-install` generated this repo for you, both are already set —
skip straight to the rebuild command below. If you started from
`nix flake init -t github:scott-whitson/emanix`, set `username` in
`flake.nix` yourself before rebuilding.

One difference between the two, and it is the point of the first: a repo
`fresh-emanix-install` generated carries `emanix-distro/`, the distribution
itself, and its `emanix` input is `path:./emanix-distro` rather than the
github URL. That is what makes this machine rebuild from the image it was
installed with, offline, and it is why `nix flake update` will never move
`emanix` on its own. To track upstream instead, change that input back to
`github:scott-whitson/emanix` and run `nix flake lock --update-input emanix`.
A repo from `nix flake init` has no `emanix-distro/` and already tracks
upstream.

`host.nix` has two fields worth a second look:

- `gpu` — `"amd"`, `"intel"` or `null`. Forces the graphics driver to load in
  the initrd, so a compositor starting from tty1 does not come up before the
  GPU does. A graphical machine with this wrong boots to a black screen.
- `hardwareModule` — optional. The name of a
  [nixos-hardware](https://github.com/NixOS/nixos-hardware) module for your
  exact machine, such as `"lenovo-thinkpad-t14-amd-gen5"`. emanix does not
  guess this for you; leave it `null` if you do not know yours.

Before the first rebuild, generate a hardware module:

    sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix

Then rebuild:

    sudo nixos-rebuild switch --flake .#$(nix eval --raw -f host.nix hostName)

Documentation: https://emanix.net
