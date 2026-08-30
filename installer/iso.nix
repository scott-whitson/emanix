# installer/iso.nix — the emanix installer ISO.
# A minimal NixOS live system (NOT an emanix host — never through mkHost) that
# carries a flake + optional host keys so a bare-metal install is:
# boot -> one command.
#
# The distribution is generic: it carries no user keys or secrets. By default
# it stages the emanix distro flake with NO keys (debug/rescue ISO). A
# consuming flake (e.g. the user's dotfiles, which holds the real hosts and
# keys) builds its own installer by importing this module and setting
#   emanix.installer.flake    = <path to their flake repo>
#   emanix.installer.keysDir  = "<absolute path to their keys dir>"  (optional)
# and re-exporting the resulting `config.system.build.isoImage`. A
# keys-carrying build must be `nix build --impure` — see keysDir below.
{ pkgs, lib, nixpkgs, disko, config, ... }:

let
  cfg = config.emanix.installer;

  # The flake repo to stage, filtered so /etc/emanix/flake is a clean,
  # buildable tree (no history/symlink/result).
  #
  # `keys` is NOT filtered out: the committed `keys/<host>_host_ed25519.pub`
  # halves are the ONLY reference fresh-emanix-install has for verifying a
  # staged private key against the actual agenix recipient
  # (`age.rekey.hostPubkey`). Excluding them made that check unsatisfiable on
  # the ISO — it warned "cannot verify" and the preflight failed closed on
  # `keys` no matter what was baked. The private halves are gitignored in the
  # consuming flake, so a git-source `flake` path cannot leak them here.
  stagedRepo = builtins.path {
    name = "emanix-flake";
    path = cfg.flake;
    filter = p: _t:
      let b = builtins.baseNameOf p;
      in b != ".git" && b != "result" && b != ".superpowers";
  };

  # Keys are only staged when the builder provides a keysDir (gitignored
  # privates + committed pubs).
  #
  # `keysDir` is a STRING, not a path, and deliberately so. As a path it was
  # coerced against the flake source — and the private halves are gitignored,
  # so a flake-relative or `self.outPath`-derived keysDir can only ever
  # contain the .pub files. The result was an ISO that looked key-carrying and
  # was not. A string is resolved here by `builtins.path`, which reads the
  # real working tree, so the privates actually land in the image. That read
  # is forbidden under pure evaluation — a keys-carrying ISO must be built
  # with `--impure` (bin/emanix-iso does this).
  hasKeys = cfg.keysDir != null && builtins.pathExists cfg.keysDir;

  stagedKeys = builtins.path {
    name = "emanix-keys";
    path = cfg.keysDir;
  };

  # Private halves present in keysDir (a .pub alone is not an identity).
  privateHalves =
    lib.filter (n: !lib.hasSuffix ".pub" n)
      (lib.attrNames (builtins.readDir cfg.keysDir));

  # disko from the flake input when exposed, else nixpkgs' package — either
  # way the installer does not `nix run` it over the network.
  diskoPkg = disko.packages.${pkgs.system}.default or pkgs.disko;
in
{
  imports = [ "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix" ];

  options.emanix.installer = {
    flake = lib.mkOption {
      type = lib.types.path;
      default = ../.;
      description = "Path to the flake repo the ISO stages at /etc/emanix/flake.";
    };
    keysDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/scott/dotfiles/keys";
      description = ''
        Absolute path, as a STRING, to a keys/ dir (host_ed25519 key pairs) to
        stage at /etc/emanix/keys. Null stages no keys.

        It must point at the working tree, NOT into the flake source: the
        private halves are gitignored, so a store-derived path stages only the
        .pub files and yields an ISO that cannot install. Reading it requires
        `nix build --impure`.
      '';
    };
  };

  config = {
    isoImage.volumeID = "emanix"; # boot menu + mount label

    # A keysDir holding only .pub files is the exact failure this module
    # shipped with: the ISO builds, boots, and then dies at the installer's
    # preflight on the target's console. Fail at build time instead.
    assertions = lib.optional hasKeys {
      assertion = privateHalves != [ ];
      message = ''
        emanix.installer.keysDir (${cfg.keysDir}) holds no private host key —
        only .pub halves. The ISO would carry no identity and
        fresh-emanix-install would fail its keys preflight on the target.
        Stage a private half, e.g.
          sudo cp /etc/ssh/ssh_host_ed25519_key keys/<host>_host_ed25519
        or set emanix.installer.keysDir = null for a keyless rescue ISO.
      '';
    };

    # The flake (+ optional keys) at fixed, /mnt-safe paths. /etc lives on the
    # live overlay, so the disko step — which mounts the target root at /mnt —
    # cannot hide it (the trap that broke USB-staged repos mounted under /mnt).
    environment.etc =
      { "emanix/flake".source = stagedRepo; }
      // lib.optionalAttrs hasKeys { "emanix/keys".source = stagedKeys; }
      // {
        "issue".text = ''
          ══ emanix installer ════════════════════════════════════════════
            flake : /etc/emanix/flake
            keys  : /etc/emanix/keys (only when a customized ISO carried them)
            install a host:  sudo fresh-emanix-install <host> [--disk /dev/X]
            check only:      sudo fresh-emanix-install <host> --check-only
            remote access:   boot with live.nixos.passwd=<pw> on the kernel
                             cmdline, then ssh nixos@<ip>
          ═════════════════════════════════════════════════════════════════
        '';
      };

    environment.systemPackages = with pkgs; [
      exfatprogs # mounting arbitrary USB sticks
      dosfstools
      diskoPkg
      (pkgs.writeShellScriptBin "fresh-emanix-install" (builtins.readFile ./fresh-emanix-install))
      # emanix-firstboot is deliberately NOT here. It runs on the INSTALLED
      # system after reboot, where os-system/firstboot.nix puts it on PATH with
      # the consumer's content — running it inside the live ISO would act on the
      # installer environment, not the machine being built. Its body also left
      # the distribution entirely (it was one deployment's tailnet join), so
      # there is nothing generic left here to bake in.
    ];

    # WiFi — the installer profile (installation-device.nix) already enables
    # NetworkManager. Point its backend at iwd so BOTH nmcli/nmtui and the
    # runbook's iwctl work, and avoid the wpa_supplicant backend that iwd is
    # mutually exclusive with (nixpkgs enables iwd automatically for this
    # backend).
    networking.networkmanager.wifi.backend = "iwd";

    # sshd for driving the target remotely. Host keys are generated fresh at
    # every boot (live tmpfs) — ephemeral by construction. The nixos user has an
    # EMPTY password on the ISO, so nothing can log in remotely until a password
    # is set (via the `live.nixos.passwd=<pw>` kernel cmdline or `sudo passwd
    # nixos` at the console).
    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = true;
    };

    # The installer runs `nixos-install --flake`, `nix run`, disko etc.
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
  };
}
