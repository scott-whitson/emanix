# The plain-value library, passed to modules as `emanixLib` via specialArgs.
#
# NOT the whole of lib/. disk.nix (mkDisk) and mkHost.nix sit beside themes.nix
# but are deliberately absent from this attrset: both are consumed from OUTSIDE
# a module evaluation — by a consuming flake's outputs — so they are exported
# as flake outputs (`emanix.lib.mkDisk`, `emanix.lib.mkHost`) instead. The file
# layout suggests otherwise, hence this note: `emanixLib.mkDisk` does not
# exist, and is not meant to.
{
  theme = import ./themes.nix;
}
