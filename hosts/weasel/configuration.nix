{ lib, ... }:

{
  # weasel — NixOS-WSL work distro (design spec 2026-07-21).
  # No hardware/disko/EWM layer: nixos-wsl supplies boot + mounts, WSLg
  # supplies the display. Home layer arrives via the flake's hmModule with
  # profile "wsl" (same home as the retired scott@work standalone config).
  imports = [
    ../../ioshi/os-system/base.nix
    ../../ioshi/hi-hardware/net/tailscale.nix
    ../../ioshi/hi-hardware/net/ssh.nix
    ../../ioshi/i-intelligence/secrets.nix
  ];

  # Hostname comes via wsl.conf, NOT networking.hostName: NixOS setting the
  # hostname at activation breaks WSL's systemd user-session bootstrap when
  # another distro is running (NixOS-WSL#888 — our exact symptom: user@1000
  # EBUSY, WSL squatting the cgroup with a hidden-pidns session).
  networking.hostName = "";

  wsl = {
    enable = true;
    defaultUser = "scott";
    wslConf = {
      # Carried over from the hand-tuned Debian /etc/wsl.conf (2026-05-13
      # plan9 tuning): metadata mounts + no Windows PATH pollution.
      automount.options = "metadata,uid=1000,gid=1000,umask=022,fmask=11,case=off,msize=262144";
      interop.appendWindowsPath = false;
      network.hostname = "weasel";
    };
  };

  # WSL owns /etc/resolv.conf. tailscale.nix enables resolved for the real
  # hosts; on WSL it would fight the generated resolv.conf — force it off
  # and keep tailscale's hands off DNS (connectivity only, as the userspace
  # daemon on Debian worked today).
  services.resolved.enable = lib.mkForce false;
  services.tailscale.extraUpFlags = [ "--accept-dns=false" ];

  # ALL WSL2 distros share one network namespace with the Windows host's VM,
  # so weasel collides with the Debian distro until Debian retires
  # (found live, first boot 2026-07-22):
  # - Two kernel-mode tailscaleds fight over routing table 52 and the
  #   100.100.100.100 MagicDNS route — weasel's daemon (accept-dns=false)
  #   won and BLACKHOLED Debian's DNS. Userspace networking adds no tun and
  #   no routes: zero interference, still direct QUIC to datacore.
  #   AFTER DEBIAN RETIRES: flip to a real interface name for kernel-mode
  #   WireGuard (e.g. "tailscale0").
  # - Debian's sshd holds port 22 — weasel's sshd cannot bind it.
  # - Debian's syncthing owns GUI 8384 / sync 22000 — weasel's moved to
  #   8385/22001 (flake.nix weasel HM block).
  services.tailscale.interfaceName = "userspace-networking";
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
      builder.gc = {
        enabled = true;
        defaultKeepStorage = "25GB";
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
