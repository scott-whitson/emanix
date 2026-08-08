# ioshi Phase D — secrets (agenix) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox syntax.

**Goal:** Introduce agenix and manage the one real long-lived secret — the OpenRouter `auth.json` — so a fresh install auto-provisions it. The ephemeral Tailscale authkey stays a documented install-time step (Phase E).

**Architecture:** `agenix` flake input + `agenix.nixosModules.default` wired via `lib/mkHost`. One secret `secrets/openrouter-auth.age`, encrypted to {eminix, zord-old, swhitson-11l}, decrypted at activation to `/home/scott/.pi/agent/auth.json` (owner scott, 0600). Hosts decrypt with their SSH host key (`age.identityPaths` default `/etc/ssh/ssh_host_ed25519_key`).

## Global Constraints

- **No Nix / no agenix CLI on WSL.** Encrypt the placeholder + build on zord-old via the bundle loop.
- **Secret boundary:** this plan commits a **placeholder** (`REPLACE-ME`) only. The real OpenRouter keys are inserted by Scott via `agenix -e secrets/openrouter-auth.age` (from the WSL box, using `~/.ssh/id_ed25519`). Claude never handles the real key.
- **eminix host key:** private key lives at `~/.ssh/eminix_host_ed25519` (OUT of repo); its `.pub` is a recipient. The private key must be injected at `/etc/ssh/ssh_host_ed25519_key` during the T14 install (Phase E) or agenix can't decrypt on eminix.
- Commits: no `Co-Authored-By`; scoped `git add`; push after the task.
- **Recipients (public keys):**
  - eminix: `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHiZAqCjE7nX2iXAlZDdZIzURl/X55ljlbpVHNlN9Za8 root@eminix`
  - zord-old: `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBp0MtitZy/niGsNtI2BzKER7UtKT6R9+wMhrS/X2pdB root@zord-old`
  - scott (admin/edit): `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINW1gKUfmcHDWf02SHUpZuIZEqq7qk4IJfmd8hlLAUQi swhitson-11l`

---

## Task D1: agenix infra + openrouter secret

**Files:**
- Modify: `flake.nix` (agenix input + output arg + pass to mkHost)
- Modify: `lib/mkHost.nix` (accept agenix; add its module)
- Create: `secrets/secrets.nix` (agenix rules), `secrets/openrouter-auth.age` (placeholder)
- Create: `ioshi/i-intelligence/secrets.nix` (age.secrets declaration)
- Modify: `profiles/eminix.nix` (import it)

- [ ] **Step 1: flake input** — add to `inputs`:
```nix
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```
Add `agenix` to the `outputs = { … }:` arg set.

- [ ] **Step 2: mkHost accepts + wires agenix**

`lib/mkHost.nix` first-arg set gains `agenix`; add `agenix.nixosModules.default` to the `modules` list. In `flake.nix`, add `agenix` to the `import ./lib/mkHost.nix { … }` call.

- [ ] **Step 3: `secrets/secrets.nix`**
```nix
let
  eminix  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHiZAqCjE7nX2iXAlZDdZIzURl/X55ljlbpVHNlN9Za8 root@eminix";
  zordold = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBp0MtitZy/niGsNtI2BzKER7UtKT6R9+wMhrS/X2pdB root@zord-old";
  scott   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINW1gKUfmcHDWf02SHUpZuIZEqq7qk4IJfmd8hlLAUQi swhitson-11l";
in
{
  "openrouter-auth.age".publicKeys = [ eminix zordold scott ];
}
```

- [ ] **Step 4: placeholder `secrets/openrouter-auth.age`** (encrypt on zord-old; format matches what `scott-openrouter.el` reads)

On zord-old, encrypt to the 3 recipients:
```bash
printf '%s' '{"openrouter-management":{"key":"REPLACE-ME-management"},"openrouter":{"key":"REPLACE-ME"}}' \
  | nix run nixpkgs#age -- -a \
    -r "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHiZAqCjE7nX2iXAlZDdZIzURl/X55ljlbpVHNlN9Za8 root@eminix" \
    -r "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBp0MtitZy/niGsNtI2BzKER7UtKT6R9+wMhrS/X2pdB root@zord-old" \
    -r "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINW1gKUfmcHDWf02SHUpZuIZEqq7qk4IJfmd8hlLAUQi swhitson-11l" \
    -o openrouter-auth.age
```
scp it back into `~/dotfiles/secrets/openrouter-auth.age`.

- [ ] **Step 5: `ioshi/i-intelligence/secrets.nix`** (NixOS module)
```nix
{ ... }:
{
  age.secrets.openrouter-auth = {
    file = ../../secrets/openrouter-auth.age;
    path = "/home/scott/.pi/agent/auth.json";
    owner = "scott";
    group = "users";
    mode = "0600";
  };
}
```

- [ ] **Step 6: import it in `profiles/eminix.nix`** — add `../ioshi/i-intelligence/secrets.nix` to the imports.

- [ ] **Step 7: flake.lock** — commit flake.nix, sync, `nix flake lock` on zord-old, scp `flake.lock` back, amend (same dance as Phase C1).

- [ ] **Step 8: Sync + verify (build-time; decryption is activation-time so only wiring is checked here)**
```bash
nix build --no-link .#nixosConfigurations.eminix.config.system.build.toplevel && echo "eminix OK"
nix build --no-link .#nixosConfigurations.zord-old.config.system.build.toplevel && echo "zord-old OK"
echo "secret path: $(nix eval --raw .#nixosConfigurations.eminix.config.age.secrets.openrouter-auth.path 2>/dev/null)"  # /home/scott/.pi/agent/auth.json
nix flake check 2>&1 | tail -1
```
Expected: both build; secret path correct; `all checks passed!`.

- [ ] **Step 9: Commit + push** (`flake.nix`, `flake.lock`, `lib/mkHost.nix`, `secrets/`, `ioshi/i-intelligence/secrets.nix`, `profiles/eminix.nix`)

---

## Handoff (Scott — the parts Claude must NOT do)

1. **Insert the real OpenRouter keys:** from the WSL box,
   `cd ~/dotfiles && nix run github:ryantm/agenix -- -e secrets/openrouter-auth.age -i ~/.ssh/id_ed25519`
   replace the `REPLACE-ME` values, save. Commit the re-encrypted `.age`.
   (Verify decrypt on zord-old after `nixos-rebuild switch`: `cat ~/.pi/agent/auth.json`.)
2. **Safeguard `~/.ssh/eminix_host_ed25519`** — this private key must be injected to `/etc/ssh/ssh_host_ed25519_key` on the T14 at install, or eminix can't decrypt its secrets. Wired into the Phase E runbook.

## Final acceptance (Phase D)

- [ ] agenix input locked; `agenix.nixosModules.default` active on both hosts.
- [ ] `secrets/secrets.nix` lists the 3 recipients; `openrouter-auth.age` present (placeholder until Scott inserts real keys).
- [ ] `age.secrets.openrouter-auth.path == /home/scott/.pi/agent/auth.json`, owner scott.
- [ ] eminix + zord-old build; `nix flake check` passes.
- [ ] Real-key insertion + host-key safeguarding handed to Scott (documented above).
