# The only machine-specific file in this repo. `fresh-emanix-install` writes it
# during an interactive install; everything else in the template is static and
# reads from here. Edit it by hand and rebuild.
{
  hostName = "emanix";
  device = "/dev/vda";
  luks = false;
  filesystem = "btrfs";
  swapSize = "0";
}
