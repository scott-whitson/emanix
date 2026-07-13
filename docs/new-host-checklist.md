# New NixOS host checklist

Everything the flake cannot do by itself, in order. Learned the hard way
on zord-old (2026-07-12/13). The flake handles all software, services,
EWM, swaylock, syncthing folder config, pi seeding, and input tuning —
these steps are the machine's identity and secrets.

## 0. Before the install

- [ ] Create `hosts/<name>/configuration.nix` — copy an existing host,
      then: new `networking.hostName`, its own hardware module under
      `modules/nixos/hardware/`, and `system.stateVersion` set to the
      CURRENT release (never copied from an older host).
- [ ] Add `nixosConfigurations.<name>` to `flake.nix`.
- [ ] Validate without root: `nix build .#nixosConfigurations.<name>.config.system.build.toplevel`

## 1. Install + first boot

- [ ] `nixos-install --flake ...#<name>`, boot, log in on tty1
      (EWM launches from the login shell — see modules/nixos/ewm.nix).
- [ ] Clone the repo to its permanent home: `~/projects/dotfiles`
      (matches the `scott.dotfiles.path` default; never "-tmp" names).
      Remote: GitHub, or `scott@datacore:projects/dotfiles` (hostname,
      not a LAN IP — IPs break off-LAN).

## 2. Tailnet (headscale on datacore — there is NO browser login)

- [ ] On datacore: `docker exec headscale headscale preauthkeys create --user 1 --expiration 1h`
- [ ] On the new host: `echo '<key>' | sudo tee /var/lib/tailscale-authkey`
      then `sudo systemctl restart tailscaled-autoconnect`
      (the login-server URL is baked into the flake via extraUpFlags).
- [ ] Verify: `tailscale status`, `ping datacore`.
- [ ] Delete the key file copies afterwards: the tailscale state dir holds
      the real identity from here on. `sudo rm /var/lib/tailscale-authkey`.

## 3. SSH

- [ ] The host's users get keys declaratively
      (`users.users.scott.openssh.authorizedKeys.keys` in the host file).
- [ ] Generate the host user's own keypair and add it wherever this
      machine must reach (GitHub, datacore, siblings).

## 4. Syncthing pairing (two-sided; the flake only does OUR side)

- [ ] Rebuild once so syncthing starts and generates the device identity.
- [ ] Get the ID: `curl -s -H "X-API-Key: $(grep -oP '(?<=<apikey>)[^<]+' ~/.local/state/syncthing/config.xml)' http://127.0.0.1:8384/rest/system/status | jq -r .myID`
- [ ] On datacore (GUI :8384 or REST): add the device, share `pi-agent`
      and `docs` with it.
- [ ] **WAIT for `docs` to reach 100% before using any org tooling.**
      C-c q (and anything create-if-missing) races the first sync and
      the fresh template WINS the conflict. Watch:
      `/rest/db/completion?folder=docs`.

## 5. Pi agent

- [ ] `npm install -g --prefix ~/.local --ignore-scripts @earendil-works/pi-coding-agent`
      (nodejs is already in home packages; ~/.local/bin is on PATH).
- [ ] Copy auth from a sibling machine (NEVER synced, by design):
      `ssh datacore 'cat ~/.pi/agent/auth.json' > ~/.pi/agent/auth.json && chmod 600 ~/.pi/agent/auth.json`
- [ ] settings.json is seeded by home-manager on first activation;
      pi installs its extensions from the `packages` list on first run.
- [ ] Launch pi, confirm the hindsight segment appears in the bar
      (hindsight API = `http://datacore:8888`, needs the tailnet up).

## 6. Sanity checks

- [ ] `s-d` launches ghostty/firefox · `s-l` locks (catppuccin swaylock)
- [ ] lid close → suspend → wake to lock screen
- [ ] modeline shows time/battery/volume/wifi/cpu/ram/gpu
- [ ] `M-x vterm` works · tap-to-click + natural scroll work
- [ ] `~/.emacs.d` does NOT exist (if it does, something ran emacs
      wrong — it shadows ~/.config/emacs and splits org-roam state)
- [ ] `ssh datacore` / `ssh swhitson-11l` resolve via MagicDNS

## Retire a machine

- [ ] Remove its device from datacore syncthing (folders first, then device)
- [ ] `docker exec headscale headscale nodes delete -i <id>` on datacore
- [ ] Revoke its authorizedKeys entries in the flake
