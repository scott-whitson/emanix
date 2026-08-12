{ ... }:
{
  # Syncthing — pi session + docs sync with datacore.
  # Device IDs are public keys, safe to commit. Pairing is two-sided: datacore
  # must also add each host's device ID and share the folders (datacore:8384).
  # Per-machine files are excluded by the .stignore pi.nix writes.
  services.syncthing = {
    enable = true;
    user = "scott";
    group = "users";
    dataDir = "/home/scott";
    configDir = "/home/scott/.local/state/syncthing";
    openDefaultPorts = true;
    overrideDevices = true;
    overrideFolders = true;
    settings = {
      devices.datacore.id =
        "FXOPHIF-EMJAP6C-CLI6PB4-HCLUDMK-RJ3PXLE-GIV4IJ7-3NMTE35-YHRNIAI";
      folders.pi-agent = {
        id = "pi-agent";
        label = "pi-agent";
        path = "/home/scott/.pi/agent";
        devices = [ "datacore" ];
      };
      folders.docs = {
        id = "docs";
        label = "docs";
        path = "/home/scott/docs";
        devices = [ "datacore" ];
      };
      folders.downloads = {
        id = "downloads";
        label = "downloads";
        path = "/home/scott/downloads";
        devices = [ "datacore" ];
      };
      folders.work-projects = {
        id = "work-projects";
        label = "work-projects";
        path = "/home/scott/projects/work";
        devices = [ "datacore" ];
      };
    };
  };

  # Ported from base/systemd's syncthing.service.d/override.conf (a user-unit
  # drop-in) during the stow retirement. On NixOS syncthing runs as a *system*
  # service (services.syncthing above), not the user unit the drop-in targeted,
  # so the ordering belongs here instead.
  systemd.services.syncthing = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
