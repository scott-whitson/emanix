{ config, lib, pkgs, ... }:

let
  hs = config.eminix.pi.hindsight;

  # pi-hindsight's config is RENDERED, not shipped as a static file. The three
  # facts that actually vary per deployment (endpoint, bank, tags) were the
  # only personal content left in this tree, and a static file gave consumers
  # no seam to change them: extensions/ deploys as one directory, so a
  # consumer cannot override a single file inside it.
  hindsightSettings = {
    inherit (hs) apiUrl apiKey bankId constantTags;
    observationScopes = [ [ "harness:pi" ] ];
    autoRecallTags = [ "harness:pi" ];
    autoRecallTagsMatch = "any_strict";
    autoRecallPersist = false;
    autoRecallDisplay = false;
    maxRecallTokens = 2048;
    toolsEnabled = [ "retain" "recall" "reflect" ];
  } // hs.extraSettings;

  # .jsonc accepts strict JSON, so toJSON is safe here. The explanatory prose
  # that used to live in the file's comments is on the options below, where it
  # is discoverable without opening a generated store path.
  hindsightConfig =
    pkgs.writeText "pi-hindsight-config.jsonc" (builtins.toJSON hindsightSettings);

  # extensions/ ships as one store directory (see home.file below), so the
  # rendered config is grafted in with a copy rather than an overlay.
  piExtensions = pkgs.runCommand "eminix-pi-extensions" { } ''
    cp -r ${./pi/agent/extensions} $out
    chmod -R u+w $out
    mkdir -p $out/pi-hindsight
    cp ${hindsightConfig} $out/pi-hindsight/config.jsonc
  '';
in
{
  options.eminix.pi = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        This host actually runs the pi agent, so it gets the OpenRouter
        credential symlinked from agenix.

        Set false on hosts that hold ~/.pi/agent only as a Syncthing peer
        (they receive the secret via agenix — a recipient of the secret is a
        per-host agenix concern — but do not run pi, so there is no reason to
        deploy the symlink there). This option gates the symlink only; it
        does not gate, and never gated, recipient status.
      '';
    };

    settingsSource = lib.mkOption {
      type = lib.types.path;
      default = ./pi/agent/settings.json;
      description = ''
        Path to the pi agent settings.json used to SEED ~/.pi/agent/settings.json.
        Defaults to the distro's generic file. Consumers that want their own
        model/provider choices point this at a file in their own checkout.
      '';
    };

    hindsight = {
      apiUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:8888";
        example = "http://datacore:8888";
        description = ''
          pi-hindsight endpoint. A self-hosted instance reachable over the
          tailnet works here, but note that a host on USERSPACE tailscale has
          no route to a tailnet IP and cannot reach it.
        '';
      };

      apiKey = lib.mkOption {
        type = lib.types.str;
        default = "local";
        description = ''
          Client auth for the hindsight server. This lands in a WORLD-READABLE
          store path — leave it at the placeholder and set the HINDSIGHT_API_KEY
          environment variable instead if your endpoint needs a real secret.
        '';
      };

      bankId = lib.mkOption {
        type = lib.types.str;
        default = "default";
        example = "pi-work";
        description = "Hindsight bank that retained observations are written to.";
      };

      constantTags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "harness:pi" ];
        example = [ "harness:pi" "user:alice" ];
        description = ''
          Tags attached to every observation. Independent of observationScopes
          and autoRecallTags, which stay at the distro default unless you
          override them through extraSettings.
        '';
      };

      extraSettings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        example = { maxRecallTokens = 4096; };
        description = ''
          Merged over the generated config, last write wins. For keys this
          module does not expose as options.
        '';
      };
    };
  };

  config = {
    # Pi coding agent configuration.
    # Pi itself is installed declaratively via packages.nix (pi-coding-agent from
    # nixpkgs). This module only manages the config files.
    # settings.json is SEEDED, not owned: pi mutates it at runtime (model
    # toggles, lastChangelogVersion), so a read-only store symlink breaks pi —
    # and without the real file's `packages` list, pi loads no extensions at
    # all (found 2026-07-13: zord-old had a {theme,model} stub → no hindsight
    # bar). After the first activation the machine's copy is authoritative;
    # it is stignored from the pi-agent sync, so per-machine drift is fine.
    home.activation.piSettingsSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -f "$HOME/.pi/agent/settings.json" ] || [ -L "$HOME/.pi/agent/settings.json" ]; then
        run rm -f "$HOME/.pi/agent/settings.json"
        run install -m 600 ${config.eminix.pi.settingsSource} "$HOME/.pi/agent/settings.json"
      fi
    '';

    # OpenRouter keys: symlink into the HM-owned ~/.pi/agent from the agenix
    # secret at /run/agenix/openrouter-auth. HM owns this dir, so there is no
    # root/user ownership collision (agenix no longer creates ~/.pi/agent).
    # .stignore already excludes /auth.json from Syncthing.
    #
    # Gated on eminix.pi.enable, NOT on "is this a NixOS host with agenix".
    # The secret itself (e.g. an OpenRouter auth key) is declared by the
    # consuming flake; this module only symlinks the decrypted secret into the
    # pi agent's home when this host actually runs pi.
    home.file.".pi/agent/auth.json" = lib.mkIf config.eminix.pi.enable {
      source = config.lib.file.mkOutOfStoreSymlink "/run/agenix/openrouter-auth";
    };

    home.file.".pi/agent/AGENTS.md" = {
      # Flake-relative path literal (not a string): the file is copied into the
      # store, so hosts without a dotfiles checkout still get it, and pure
      # evaluation works (an absolute /home/... path aborts nixos-install).
      source = ./pi/agent/AGENTS.md;
    };

    # Same reasoning as AGENTS.md above, applied to whole directories: flake-
    # relative path literals copy skills/ and extensions/ into the store, so
    # pi actually loads them (found 2026-08-07: after the stow retirement
    # these were dangling symlinks into a deleted base/pi/, and pi silently
    # loaded zero skills/extensions).
    home.file.".pi/agent/skills".source = ./pi/agent/skills;
    # piExtensions, not the bare path literal: pi-hindsight/config.jsonc is
    # rendered from eminix.pi.hindsight.* and grafted into the tree (see the
    # let block). Everything else in extensions/ is copied through unchanged.
    home.file.".pi/agent/extensions".source = piExtensions;

    # Pi themes are generated by bin/gen-pi-theme.py during bootstrap.
    # HM doesn't manage the generated output — the runtime theme switcher handles it.

    # Syncthing folder marker and ignore file for the ~/.pi/agent/ sync folder.
    # These live inside the folder so Syncthing recognizes it.
    home.file.".pi/agent/.stfolder" = {
      text = "";
      force = true; # Ensure it exists even if Syncthing clears it
    };

    home.file.".pi/agent/.stignore" = {
      text = ''
        // Non-portable — API keys, per-machine auth
        /auth.json

        // Owned by home-manager/stow per host (nix store symlinks on NixOS —
        // syncing these caused the settings.json sync-conflict of 2026-07-11)
        /settings.json
        /AGENTS.md
        /skills
        /extensions

        // Generated per machine by the theme switcher
        // NB: no trailing slashes — syncthing ignores are not gitignore;
        // "/npm/" matches nothing (verified 2026-07-13: dirs leaked to zord-old)
        /themes

        // Architecture-specific install artifacts — reinstall via pi packages on each machine
        /npm
        /git
        /bin

        // Local-only runtime state
        /intercom
        /chains
        /epimetheus
        /run-history.jsonl
        /extensions/pi-hindsight/queues

        // Temp files
        /settings.json.tmp
      '';
    };
  };
}
