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

  networking.hostName = "weasel";

  wsl = {
    enable = true;
    defaultUser = "scott";
    wslConf = {
      # Carried over from the hand-tuned Debian /etc/wsl.conf (2026-05-13
      # plan9 tuning): metadata mounts + no Windows PATH pollution.
      automount.options = "metadata,uid=1000,gid=1000,umask=022,fmask=11,case=off,msize=262144";
      interop.appendWindowsPath = false;
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
  # - Debian's tailscaled owns the tun device "tailscale0" — weasel's
  #   tailscaled gets EBUSY without its own interface name.
  # - Debian's sshd holds port 22 — weasel's sshd cannot bind it.
  # After Debian is unregistered these could revert, but there's no need to.
  services.tailscale.interfaceName = "weasel0";
  services.openssh.ports = [ 2222 ];

  # WSL's session bootstrap does not reliably create a logind session, so
  # user services (emacs daemon, syncthing) would never start. Lingering
  # boots scott's user manager unconditionally.
  users.users.scott.linger = true;

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
