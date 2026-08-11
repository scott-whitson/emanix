{ lib, ... }:

{
  # whistle — NixOS-WSL work distro (design spec 2026-07-21, named weasel
  # until the 2026-08-04 rename).
  # No hardware/disko/EWM layer: nixos-wsl supplies boot + mounts, WSLg
  # supplies the display. Home layer arrives via the flake's hmModule with
  # profile "wsl" (same home as the retired scott@work standalone config).

  # os-system/base.nix, hi-hardware/net/{tailscale,ssh}.nix and
  # i-intelligence/secrets.nix: now supplied by the eminix core
  # (profiles/eminix.nix, via mkHost) — this used to hand-import exactly
  # this set before whistle moved onto mkHost. Redeclaring them here would
  # only dedup by path, not signal ownership.

  # Hostname comes via wsl.conf, NOT networking.hostName: NixOS setting the
  # hostname at activation breaks WSL's systemd user-session bootstrap when
  # another distro is running (NixOS-WSL#888 — our exact symptom: user@1000
  # EBUSY, WSL squatting the cgroup with a hidden-pidns session).
  networking.hostName = lib.mkForce "";

  # networking.hostName must stay empty (above), which leaves the generation
  # label reading "unnamed" — system.name restores a real label without
  # touching the hostname WSL bootstraps against.
  system.name = "whistle";

  wsl = {
    enable = true;
    defaultUser = "scott";

    # wsl.conf says interop.enabled=true, but nothing was ever registering the
    # handler: WSL's systemd generator drops an override into
    # systemd-binfmt.service / binfmt-support.service that re-registers
    # WSLInterop, and NixOS generates NEITHER unit unless boot.binfmt has
    # registrations — so both drop-ins sat inert and /proc/sys/fs/binfmt_misc
    # had no WSLInterop at all. Every .exe call then dies with "cannot execute
    # binary file" (debugged 2026-08-10, where it masked a WSLg gfxredir
    # failure by breaking the powershell.exe used to diagnose it).
    # register=true emits the boot.binfmt entry (MZ magic -> /init, fixBinary
    # + preserveArgvZero), which creates the unit AND registers the handler.
    # Upstream defaults this off to "use the existing registration", an
    # assumption that only holds on non-NixOS distros.
    # Knock-on: once the unit exists, WSL's drop-in DOES apply and resets
    # ExecStart, so the live registration is WSL's ":WSLInterop:M::MZ::/init:P"
    # and /etc/binfmt.d/nixos.conf goes unread. Interop works either way, but
    # any future boot.binfmt entry (qemu/aarch64 cross) would silently not be
    # applied — drop protectBinfmt in wsl.conf if that day comes.
    interop.register = true;

    wslConf = {
      # Carried over from the hand-tuned Debian /etc/wsl.conf (2026-05-13
      # plan9 tuning): metadata mounts + no Windows PATH pollution.
      automount.options = "metadata,uid=1000,gid=1000,umask=022,fmask=11,case=off,msize=262144";
      interop.appendWindowsPath = false;
      network.hostname = "whistle";
    };
  };

  # WSL owns /etc/resolv.conf. tailscale.nix enables resolved for the real
  # hosts; on WSL it would fight the generated resolv.conf — force it off
  # and keep tailscale's hands off DNS (connectivity only, as the userspace
  # daemon on Debian worked today).
  services.resolved.enable = lib.mkForce false;
  services.tailscale.extraUpFlags = [ "--accept-dns=false" ];

  # Debian retired 2026-08-04 — whistle is the only distro, so kernel-mode
  # WireGuard is safe again (during coexistence, two kernel tailscaleds
  # fought over routing table 52 and blackholed Debian's DNS; see
  # docs/ioshi/whistle.md gotchas for the history). sshd stays on 2222 and
  # syncthing on 8385/22001 — nothing depends on the old numbers and the
  # muscle memory/config (eminix ssh config, datacore) already points here.
  services.tailscale.interfaceName = "tailscale0";
  services.openssh.ports = [ 2222 ];

  # WSL's session bootstrap execs a HARDCODED /usr/bin/systemctl to start
  # the user session (microsoft/WSL#13236); NixOS has no /usr/bin/systemctl,
  # so WSL falls back to hand-parking session processes in a self-made
  # user@1000.service cgroup — which then blocks systemd's real user manager
  # with "Failed to spawn executor: Device or resource busy". The symlink
  # lets WSL's call succeed, so emacs/syncthing user services can live.
  systemd.tmpfiles.rules = [
    "L+ /usr/bin/systemctl - - - - /run/current-system/sw/bin/systemctl"
  ];

  # Belt to the symlink's suspenders: lingering boots scott's user manager
  # even when no WSL session has been opened yet (headless starts).
  users.users.scott.linger = true;

  # WSL 2.6+ "user session" machinery pre-populates user@1000.service's
  # cgroup with its own hidden-pidns processes when a session is requested
  # during boot, and systemd 260's clone-into-cgroup spawn then fails with
  # "Failed to spawn executor: Device or resource busy" — no user manager,
  # so no emacs/syncthing (microsoft/WSL#13186 lineage; verified live
  # 2026-07-22 on WSL 2.7.3). cgroup.kill clears the squatters (it reaches
  # foreign pid namespaces); once user@1000 is genuinely active, later WSL
  # session requests see it and do not squat again.
  systemd.services.wsl-user-session-rescue = {
    description = "Heal user@1000 after WSL session-cgroup squatting";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      sleep 15
      if [ "$(systemctl is-active user@1000.service)" != active ]; then
        cg=/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service
        if [ -d "$cg" ]; then
          echo 1 > "$cg/cgroup.kill" 2>/dev/null || true
          sleep 2
        fi
        systemctl reset-failed user@1000.service 2>/dev/null || true
        systemctl start user@1000.service
      fi
    '';
  };

  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      # The 2026-07-21 lesson: 137 GB of buildkit cache in 3 days. Cap it.
      # 2026-08-11: the cap held (cache sat at 23.13 GB) but 25 GB is most of a
      # lean WSL disk on its own, and the vhdx only ever grows to the high-water
      # mark. 8 GB still covers a warm pearl rebuild.
      builder.gc = {
        enabled = true;
        defaultKeepStorage = "8GB";
      };
    };
  };

  # The ONE long-lived dev DB (spec decision: worktree DBs stay compose).
  # Env file carries POSTGRES_PASSWORD; hand-placed in the cutover (it must
  # match the value pearl-platform's .env derives its DATABASE_URL from).
  virtualisation.oci-containers = {
    backend = "docker";
    containers.pearl-platform-db = {
      image = "pgvector/pgvector:pg16";
      environment = {
        POSTGRES_USER = "pearl";
        POSTGRES_DB = "pearl";
      };
      environmentFiles = [ "/var/lib/pearl-db/env" ];
      ports = [ "5434:5432" ];
      volumes = [ "/var/lib/pearl-db/data:/var/lib/postgresql/data" ];
    };
  };

  # Vendor binaries (npm native modules, downloaded tools) without FHS pain.
  programs.nix-ld.enable = true;

  # NB: system.stateVersion records first-install release; never bump later.
  system.stateVersion = "26.11";
}
