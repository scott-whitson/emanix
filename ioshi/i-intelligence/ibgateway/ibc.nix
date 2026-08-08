{ lib, stdenvNoCC, fetchurl, unzip }:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ibc";
  version = "3.23.0";

  # IBC ships pristine. Upstream's gatewaystart.sh hardcodes its paths and is
  # NOT env-overridable, so ibgateway.nix supplies its own launcher and execs
  # scripts/displaybannerandlaunch.sh directly. Nothing here is patched.
  src = fetchurl {
    url = "https://github.com/IbcAlpha/IBC/releases/download/${finalAttrs.version}/IBCLinux-${finalAttrs.version}.zip";
    hash = "sha256-C9A8cT8EwKZDZ6u9PVpA0ij8wvuWnJJ71829hbrdrEs=";
  };

  nativeBuildInputs = [ unzip ];

  # The zip has no top-level directory — it unpacks flat.
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r . "$out/"
    chmod +x "$out"/*.sh "$out"/scripts/*.sh
    runHook postInstall
  '';

  meta = {
    description = "IBC — automates Interactive Brokers Gateway/TWS login";
    homepage = "https://github.com/IbcAlpha/IBC";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
})
