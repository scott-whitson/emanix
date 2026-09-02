# Clean Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `fresh-emanix-install` install a host the staged flake has never heard of, and give the resulting machine an Emacs welcome buffer that can turn itself into a real config repo.

**Architecture:** One new `templates/default/` flake skeleton is the single source both the installer and `emanix-init` read. The installer writes exactly one generated file (`host.nix`) and installs; `emanix-init` later adopts that into a git repo and validates it. A `*emanix-welcome*` buffer orients the user and offers `emanix-init` when no repo exists. Two new flake checks guard the template's evaluability and the buffer's key claims.

**Tech Stack:** Nix flakes, disko, NixOS modules, bash (`writeShellApplication`, shellcheck at build time), Emacs Lisp + ERT.

**Spec:** `docs/superpowers/specs/2026-09-02-emanix-clean-install-design.md`

## Global Constraints

- **No absolute `/home/<user>` paths in shipped elisp or scripts.** Derive from `$HOME` / `user-login-name`. `checks/arc-glue.nix` exists because this defect ran undetected for six weeks.
- **The distribution ships no host facts.** No disk layout, hostname, or user identity in `lib/` or `ioshi/`. The parameterized layout lives in `templates/default/`, which becomes the *consumer's* repo.
- **New elisp loaded at startup must not require packages or touch the network** — the `fallback.el` rule. A first boot must not be broken by the welcome buffer.
- **Never shadow a built-in Emacs library.** `arc-mode` is real; check any new feature name.
- **Scripts get `writeShellApplication`**, not a repo `bin/`, so shellcheck runs at build time. emanix has no `bin/` directory and must not gain one.
- **The existing pre-staged install path must not change behaviour.** Interactive mode is additive.
- **Deviation from the spec, deliberate:** the spec says `bin/emanix-init`. emanix packages scripts instead (see `ioshi/os-system/firstboot.nix`), so this plan ships `emanix-init` as a `writeShellApplication` from `ioshi/os-system/init.nix` with its body in `installer/emanix-init.sh`.

---

### Task 1: The `templates/default/` skeleton and its evaluation check

**Files:**
- Create: `templates/default/flake.nix`
- Create: `templates/default/host.nix`
- Create: `templates/default/disko.nix`
- Create: `templates/default/configuration.nix`
- Create: `templates/default/README.md`
- Create: `checks/template-host.nix`
- Modify: `flake.nix` (add `templates` output; add `template-host` to `checks.${system}`)

**Interfaces:**
- Produces: `templates/default/host.nix` returning an attrset with exactly the keys `hostName` (string), `device` (string), `luks` (bool), `filesystem` (one of `"btrfs"`, `"ext4"`), `swapSize` (string, `"0"` meaning none). Task 2's installer writes this file; Task 3's `emanix-init` reads it. `templates/default/disko.nix` is a function `{ host }: { disko.devices... }`.
- Produces: flake output `templates.default = { path = ./templates/default; description = ...; }`.

- [ ] **Step 1: Write the failing check**

Create `checks/template-host.nix`:

```nix
# The template is the ONLY thing a stranger's machine is built from, and a
# template that does not evaluate produces a failure on someone else's console
# with no context to debug it. So it is evaluated here, on every flake check,
# against a fixture host.nix.
#
# It deliberately does NOT go through the template's own flake.nix: that
# declares `emanix` as a github input, which the build sandbox cannot fetch.
# The modules are evaluated against THIS tree instead, which is the thing that
# actually drifts.
{ pkgs, mkHost, ... }:
let
  fixture = {
    hostName = "templatehost";
    device = "/dev/vda";
    luks = false;
    filesystem = "btrfs";
    swapSize = "0";
  };
in
pkgs.runCommand "emanix-template-host" { } ''
  echo ${
    builtins.unsafeDiscardStringContext
      (mkHost {
        hostName = fixture.hostName;
        role = "workstation";
        username = "templateuser";
        hardware = ../checks/stub-hardware.nix;
        extraModules = [
          (import ../templates/default/disko.nix { host = fixture; })
          (import ../templates/default/configuration.nix)
        ];
        homeModules = [{ }];
      }).config.system.build.toplevel.drvPath
  } > $out
''
```

- [ ] **Step 2: Run it to verify it fails**

Run: `nix build --no-link .#checks.x86_64-linux.template-host`
Expected: FAIL — `attribute 'template-host' missing`, because the flake does not expose it yet.

- [ ] **Step 3: Write the template files**

Create `templates/default/host.nix` — the ONE generated file:

```nix
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
```

Create `templates/default/disko.nix`:

```nix
# Parameterized disk layout. Lives in the TEMPLATE, not in emanix's lib/,
# because a disk layout is a fact about a machine and the distribution ships
# no machine facts.
{ host }:
let
  rootContent =
    if host.filesystem == "btrfs" then {
      type = "btrfs";
      extraArgs = [ "-f" ];
      subvolumes = {
        "@" = { mountpoint = "/"; mountOptions = [ "compress=zstd" ]; };
        "@nix" = { mountpoint = "/nix"; mountOptions = [ "compress=zstd" "noatime" ]; };
        "@home" = { mountpoint = "/home"; mountOptions = [ "compress=zstd" ]; };
      };
    } else {
      type = "filesystem";
      format = "ext4";
      mountpoint = "/";
    };

  # LUKS wraps the filesystem rather than replacing it, so the two knobs are
  # independent: ext4-on-LUKS and bare btrfs are both reachable.
  rootPartition =
    if host.luks then {
      type = "luks";
      name = "cryptroot";
      settings.allowDiscards = true;
      content = rootContent;
    } else rootContent;
in
_: {
  disko.devices.disk.main = {
    type = "disk";
    device = host.device;
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "fmask=0077" "dmask=0077" ];
          };
        };
      } // (if host.swapSize == "0" then { } else {
        swap = {
          size = host.swapSize;
          content = { type = "swap"; };
        };
      }) // {
        root = {
          size = "100%";
          content = rootPartition;
        };
      };
    };
  };
}
```

Create `templates/default/configuration.nix`:

```nix
# Minimal host config. Everything opinionated is the distribution's job; this
# file holds only what emanix cannot know.
{ lib, ... }:
{
  emanix.gui = true;

  # Opt in to autologin only if this machine's disk is encrypted. Without
  # encryption, autologin means physical access alone yields a logged-in
  # session — see ioshi/i-intelligence/ewm.nix for why this is the host's
  # decision and not the distribution's.
  # services.getty.autologinUser = "youruser";

  networking.networkmanager.enable = true;
  time.timeZone = lib.mkDefault "UTC";
  system.stateVersion = "26.11";
}
```

Create `templates/default/flake.nix`:

```nix
{
  description = "An emanix host";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    emanix = {
      url = "github:scott-whitson/emanix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, emanix, disko, ... }:
    let
      system = "x86_64-linux";
      host = import ./host.nix;
    in
    {
      nixosConfigurations.${host.hostName} = emanix.lib.mkHost {
        inherit (host) hostName;
        role = "workstation";
        username = "youruser";
        hardware = ./hardware-configuration.nix;
        extraModules = [
          disko.nixosModules.disko
          (import ./disko.nix { inherit host; })
          ./configuration.nix
          emanix.nixosModules.ewm
        ];
      };
    };
}
```

Create `templates/default/README.md`:

```markdown
# An emanix host

`host.nix` is the only file describing this machine. Everything else reads
from it.

Before the first rebuild, generate a hardware module:

    sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix

Then set `username` in `flake.nix` and rebuild:

    sudo nixos-rebuild switch --flake .#$(nix eval --raw -f host.nix hostName)

Documentation: https://emanix.net
```

- [ ] **Step 4: Wire the flake output and the check**

In `flake.nix`, add to the outputs attrset (beside `nixosModules`):

```nix
      templates.default = {
        path = ./templates/default;
        description = "An emanix host: one host.nix, a parameterized disk layout, and the distribution";
      };
```

And inside `checks.${system} = ... in { ... }`, add:

```nix
          # The template a stranger's machine is built from, evaluated on every
          # flake check. See checks/template-host.nix.
          template-host = import ./checks/template-host.nix { inherit pkgs mkHost; };
```

- [ ] **Step 5: Run the check to verify it passes**

Run: `nix build --no-link .#checks.x86_64-linux.template-host`
Expected: PASS.

Then verify the knobs actually branch, by temporarily editing the `fixture` in `checks/template-host.nix` to `luks = true; filesystem = "ext4"; swapSize = "8G";` and re-running:

Run: `nix build --no-link .#checks.x86_64-linux.template-host`
Expected: PASS with a *different* drvPath. Revert the fixture afterwards.

- [ ] **Step 6: Verify the template initialises**

Run: `cd "$(mktemp -d)" && nix flake init -t ~/projects/emanix#default && ls`
Expected: `README.md configuration.nix disko.nix flake.nix host.nix`

- [ ] **Step 7: Commit**

```bash
git add templates/default checks/template-host.nix flake.nix
git commit -m "templates: a host skeleton with a parameterized disk layout

One generated file (host.nix); disko.nix, configuration.nix and flake.nix
all read from it. The layout lives here rather than in lib/ because a disk
layout is a fact about a machine and this repo ships no machine facts.

checks/template-host.nix evaluates it on every flake check, against a
fixture host.nix and this tree's modules rather than the template's own
github input, which the sandbox cannot fetch."
```

---

### Task 2: Interactive mode in `fresh-emanix-install`

**Files:**
- Modify: `installer/fresh-emanix-install` (argument parsing, new `interactive_install` path)
- Create: `tests/installer-modes.sh`

**Interfaces:**
- Consumes: `templates/default/` from Task 1 — copies it to `/mnt/etc/nixos` and writes `host.nix` with the five keys Task 1 defined.
- Produces: nothing other tasks consume. `emanix-init` (Task 3) reads `/etc/nixos/host.nix` on the installed system.

- [ ] **Step 1: Write the failing test**

Create `tests/installer-modes.sh`:

```bash
#!/usr/bin/env bash
# Guards the mode boundary. The pre-staged path is what the existing fleet
# depends on, and it is exactly what a refactor of the interactive path would
# silently swallow — so it is asserted here rather than trusted.
#
# Run by hand: ./tests/installer-modes.sh
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/../installer/fresh-emanix-install"
fails=0

check() { # description, expected-exit, actual-exit
  if [ "$2" = "$3" ]; then
    printf '  ok   %s\n' "$1"
  else
    printf '  FAIL %s (expected exit %s, got %s)\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

# 1. A host that exists in the flake still takes the pre-staged path, and
#    --check-only still exits non-zero when its preflight is unsatisfiable
#    off-target (no UEFI, no staged key). What matters is that it reports a
#    PREFLIGHT failure, not an unknown-host one.
out="$("$SCRIPT" checkhost --check-only 2>&1)"; rc=$?
check "known-host --check-only reaches the preflight" 1 "$rc"
if grep -q "check-only: missing:" <<<"$out"; then
  printf '  ok   known-host prints the preflight checklist\n'
else
  printf '  FAIL known-host did not reach the preflight:\n%s\n' "$out"
  fails=$((fails + 1))
fi

# 2. No argument must NOT die with a usage error any more — it enters
#    interactive mode. Off-target it still fails, but for a preflight reason.
out="$("$SCRIPT" --check-only 2>&1)"; rc=$?
if grep -q "usage:" <<<"$out"; then
  printf '  FAIL no-argument still dies with a usage error\n'
  fails=$((fails + 1))
else
  printf '  ok   no-argument no longer a usage error\n'
fi

# 3. An unknown host name must be treated as a NEW host name, not an error.
out="$("$SCRIPT" brandnewbox --check-only 2>&1)"; rc=$?
if grep -qi "unknown host\|not found in the flake" <<<"$out"; then
  printf '  FAIL unknown host rejected instead of being generated\n'
  fails=$((fails + 1))
else
  printf '  ok   unknown host accepted as a new host name\n'
fi

# 4. Hostname validation must reject an RFC 1123 violation.
out="$("$SCRIPT" "Not_A_Host" --check-only 2>&1)"; rc=$?
check "invalid hostname rejected" 1 "$rc"
if grep -qi "hostname" <<<"$out"; then
  printf '  ok   invalid hostname names the problem\n'
else
  printf '  FAIL invalid hostname error did not mention the hostname:\n%s\n' "$out"
  fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && { echo "installer-modes: all good."; exit 0; }
echo "installer-modes: $fails failure(s)."; exit 1
```

Then `chmod +x tests/installer-modes.sh`.

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/installer-modes.sh`
Expected: FAIL on tests 2, 3 and 4 — the script currently dies with `usage: fresh-emanix-install <host> ...` when given no host, and has no hostname validation.

- [ ] **Step 3: Add mode detection and validation**

In `installer/fresh-emanix-install`, replace the line:

```bash
[ -n "$FLAKE_HOST" ] || die "usage: fresh-emanix-install <host> [--disk /dev/X] [--check-only]"
```

with:

```bash
# A missing host is no longer an error: it means "install a machine this flake
# has never heard of", which is the only mode a stranger can use. The host
# argument is still how the existing fleet installs, and that path is
# untouched below.
MODE=prestaged
validate_hostname() {
  # RFC 1123: lowercase alphanumeric and hyphen, no leading/trailing hyphen,
  # 1-63 chars. Rejected here rather than by nixos-install, which fails much
  # later and less clearly.
  printf '%s' "$1" | grep -qE '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'
}

known_hosts() {
  # Ask the flake rather than keeping a list here; a list is a thing that
  # drifts. Failure to evaluate means an unusable repo, so it is fatal.
  nix eval --raw "$REPO#nixosConfigurations" \
    --apply 'cfgs: builtins.concatStringsSep " " (builtins.attrNames cfgs)' \
    2>/dev/null
}
```

Immediately after `resolve_repo` is called in the preflight section (it must run first, because `known_hosts` needs `$REPO`), insert:

```bash
KNOWN="$(known_hosts)"
[ -n "$KNOWN" ] || die "could not enumerate hosts in $REPO — is it a valid flake?"

if [ -z "$FLAKE_HOST" ]; then
  MODE=interactive
elif ! printf '%s\n' $KNOWN | grep -qx "$FLAKE_HOST"; then
  MODE=interactive
fi

if [ "$MODE" = interactive ]; then
  if [ -n "$FLAKE_HOST" ] && ! validate_hostname "$FLAKE_HOST"; then
    die "hostname '$FLAKE_HOST' is not a valid hostname (RFC 1123: lowercase
letters, digits and hyphens, not starting or ending with a hyphen, 1-63 chars)."
  fi
fi
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./tests/installer-modes.sh`
Expected: PASS — `installer-modes: all good.`

- [ ] **Step 5: Commit**

```bash
git add installer/fresh-emanix-install tests/installer-modes.sh
git commit -m "installer: treat an unknown host as a new host, not an error

A missing or unrecognised host argument used to be a hard usage error, so
the installer could only ever install a machine the staged flake already
described. It now selects interactive mode instead, and validates the name
against RFC 1123 up front rather than letting nixos-install fail later and
less clearly.

The known-host list comes from the flake (nix eval over
nixosConfigurations) rather than a list in the script, because a list in a
script is a thing that drifts.

tests/installer-modes.sh asserts the pre-staged path still reaches its
preflight, which is the behaviour a refactor of the new path would
silently swallow."
```

---

### Task 3: Interactive install and `emanix-init`

**Files:**
- Modify: `installer/fresh-emanix-install` (the `interactive_install` body)
- Create: `installer/emanix-init.sh`
- Create: `ioshi/os-system/init.nix`
- Modify: `emanix.nix` (import `./ioshi/os-system/init.nix`)

**Interfaces:**
- Consumes: `templates/default/` (Task 1); `$MODE`, `$FLAKE_HOST`, `$DISK`, `$REPO` from Task 2.
- Produces: `emanix-init` on `PATH` of every emanix host. Task 4's welcome buffer calls it by name.

- [ ] **Step 1: Write the interactive prompts and generation**

In `installer/fresh-emanix-install`, add before the destructive section:

```bash
# --- Interactive mode: generate a host, then install it -----------------------
# The installer MUST write a flake before it can install: nixos-install --flake
# needs the host to exist in one. So this writes the minimum to boot, from
# templates/default, and emanix-init later adopts it into a real repo.
interactive_prompts() {
  if [ -z "$FLAKE_HOST" ]; then
    while :; do
      read -rp "Hostname for this machine: " FLAKE_HOST
      validate_hostname "$FLAKE_HOST" && break
      warn "lowercase letters, digits and hyphens only, 1-63 chars."
    done
  fi

  say "Network"
  if ping -c1 -W4 cache.nixos.org >/dev/null 2>&1; then
    echo "  already online."
  else
    warn "no route to cache.nixos.org."
    echo "  WiFi: run 'nmtui' (or 'iwctl station wlan0 connect <ssid>') in another"
    echo "  console, then return here."
    read -rp "Press Enter once the network is up: " _
    ping -c1 -W4 cache.nixos.org >/dev/null 2>&1 ||
      die "still no route to cache.nixos.org — the install downloads packages."
  fi

  read -rp "Encrypt the disk with LUKS? [Y/n] " a
  case "$a" in [Nn]*) LUKS=false ;; *) LUKS=true ;; esac

  read -rp "Root filesystem [btrfs/ext4] (btrfs): " a
  case "$a" in ext4) FSTYPE=ext4 ;; *) FSTYPE=btrfs ;; esac

  read -rp "Swap partition size, e.g. 8G, or 0 for none (0): " a
  SWAPSIZE="${a:-0}"
}

write_generated_flake() {
  # Copied rather than `nix flake init -t`, which wants to run in a git repo
  # and writes into the current directory; inside a live ISO a copy is simpler
  # and has no network or git dependency.
  install -d -m 755 /mnt/etc/nixos
  cp -r "$REPO/templates/default/." /mnt/etc/nixos/
  chmod -R u+w /mnt/etc/nixos

  cat > /mnt/etc/nixos/host.nix <<EOF
# Generated by fresh-emanix-install on $(date -u +%Y-%m-%dT%H:%M:%SZ).
# The only file in this repo describing this machine.
{
  hostName = "${FLAKE_HOST}";
  device = "${DISK}";
  luks = ${LUKS};
  filesystem = "${FSTYPE}";
  swapSize = "${SWAPSIZE}";
}
EOF

  nixos-generate-config --show-hardware-config --root /mnt \
    > /mnt/etc/nixos/hardware-configuration.nix

  sed -i "s/username = \"youruser\";/username = \"${USERNAME:-emanix}\";/" \
    /mnt/etc/nixos/flake.nix
}
```

- [ ] **Step 2: Write `emanix-init`**

Create `installer/emanix-init.sh`:

```bash
#!/usr/bin/env bash
# emanix-init — turn the config the installer generated into a repo you own.
#
# The installer writes the minimum to boot, into /etc/nixos. That is enough to
# run and not enough to live in: no git, no history, root-owned, and nowhere to
# put a secret. This moves it somewhere you can work, proves it still
# evaluates, and stops.
#
# Safe to re-run: it refuses rather than overwrites.
set -euo pipefail

say()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARNING:\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

SRC=/etc/nixos
DEST="$HOME/flake"

[ -f "$SRC/host.nix" ] ||
  die "no $SRC/host.nix — this machine was not installed by
fresh-emanix-install's interactive mode, so there is nothing to adopt. If you
already keep a flake elsewhere, you do not need this command."

[ -e "$DEST" ] && die "$DEST already exists. Move it aside first; this command
will not overwrite a directory it did not create."

say "Copying $SRC to $DEST"
mkdir -p "$DEST"
cp -r "$SRC/." "$DEST/"
chown -R "$(id -u):$(id -g)" "$DEST"
chmod -R u+w "$DEST"

say "Adding a keys directory and .gitignore"
mkdir -p "$DEST/keys"
cat > "$DEST/.gitignore" <<'EOF'
# Private host key halves. The .pub halves ARE committed: they are the
# recipients your secrets are encrypted to, and the installer verifies a
# staged private key against them.
keys/*_host_ed25519
result
result-*
EOF

# The machine already has a host key -- the installer generated it. Publishing
# the public half here is what lets secrets be encrypted TO this machine later.
if [ -f /etc/ssh/ssh_host_ed25519_key.pub ]; then
  host="$(nix eval --raw --file "$DEST/host.nix" hostName 2>/dev/null || echo host)"
  cp /etc/ssh/ssh_host_ed25519_key.pub "$DEST/keys/${host}_host_ed25519.pub"
  say "Recorded this host's public key as keys/${host}_host_ed25519.pub"
fi

say "Initialising git"
git -C "$DEST" init -q
git -C "$DEST" add -A
git -C "$DEST" -c user.email=emanix@localhost -c user.name=emanix \
  commit -q -m "initial commit: the config this machine was installed with"

say "Checking it still evaluates"
if nix flake check "$DEST" 2>&1 | tail -20; then
  say "emanix-init complete."
  echo "  Your config now lives in $DEST and is a git repo."
  echo "  Rebuild with:  sudo nixos-rebuild switch --flake $DEST"
  echo "  Documentation: https://emanix.net"
else
  warn "$DEST does not pass 'nix flake check'."
  warn "The files are in place and committed, so nothing is lost — but fix this"
  warn "before relying on it. /etc/nixos is untouched and still builds."
  exit 1
fi
```

- [ ] **Step 3: Package it**

Create `ioshi/os-system/init.nix`:

```nix
{ pkgs, ... }:
{
  # `emanix-init` on PATH for every host. Unlike emanix-firstboot, the
  # distribution owns this one's CONTENT: adopting a generated config into a
  # repo is the same operation on every machine, and it names no
  # infrastructure.
  #
  # writeShellApplication rather than a repo bin/ script, matching
  # firstboot.nix: the body is shellchecked at build time, so a broken
  # emanix-init fails the build rather than failing on a stranger's console.
  config.environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "emanix-init";
      runtimeInputs = with pkgs; [ git nix ];
      text = builtins.readFile ../../installer/emanix-init.sh;
    })
  ];
}
```

In `emanix.nix`, add to the imports list beside `./ioshi/os-system/firstboot.nix`:

```nix
    ./ioshi/os-system/init.nix
```

- [ ] **Step 4: Verify it builds and shellchecks**

Run: `nix build --no-link .#checks.x86_64-linux.role-workstation`
Expected: PASS. A shellcheck violation in `emanix-init.sh` fails here, which is the point.

Run: `nix eval --raw .#nixosModules.emanix --apply 'x: "ok"'`
Expected: `ok`

- [ ] **Step 5: Commit**

```bash
git add installer/fresh-emanix-install installer/emanix-init.sh ioshi/os-system/init.nix emanix.nix
git commit -m "installer: interactive install, and emanix-init to adopt the result

Interactive mode prompts for hostname, network, LUKS, filesystem and swap,
writes templates/default to /mnt/etc/nixos with a generated host.nix, and
installs from it. It must write a flake rather than defer: nixos-install
--flake needs the host to exist in one.

emanix-init then adopts that into ~/flake -- git init, a keys/ directory
whose .gitignore commits the .pub halves and not the private ones, the
machine's own public key recorded as a future secrets recipient, and a
nix flake check to prove it still evaluates. It refuses rather than
overwrites, and leaves /etc/nixos untouched so a failed adoption costs
nothing.

Packaged with writeShellApplication like emanix-firstboot, so the body is
shellchecked at build time instead of on a stranger's console."
```

---

### Task 4: The `*emanix-welcome*` buffer

**Files:**
- Create: `ioshi/i-intelligence/emacs/lisp/emanix-welcome.el`
- Create: `ioshi/i-intelligence/emacs/test/emanix-welcome-test.el`
- Modify: `ioshi/i-intelligence/emacs/config.el` (require + first-run hook)

**Interfaces:**
- Consumes: `emanix-init` on `PATH` (Task 3).
- Produces: `emanix-welcome` (interactive command), `emanix-welcome--config-repo` (returns a path string or nil), `emanix-welcome--dismissed-file` (returns a path string), `emanix-welcome-maybe-show` (interactive; shows unless dismissed). Task 5's check greps this file.

- [ ] **Step 1: Write the failing test**

Create `ioshi/i-intelligence/emacs/test/emanix-welcome-test.el`:

```elisp
;;; emanix-welcome-test.el --- ERT tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'emanix-welcome)

(ert-deftest emanix-welcome-dismissed-file-honours-xdg ()
  "The dismissal marker follows XDG_STATE_HOME when it is set."
  (let ((process-environment (cons "XDG_STATE_HOME=/tmp/xdgstate" process-environment)))
    (should (equal "/tmp/xdgstate/emanix/welcome-dismissed"
                   (emanix-welcome--dismissed-file)))))

(ert-deftest emanix-welcome-dismissed-file-falls-back-under-home ()
  "Without XDG_STATE_HOME it falls back to ~/.local/state, never an absolute
/home/<user> literal."
  (let ((process-environment
         (cons "XDG_STATE_HOME=" (cons "HOME=/tmp/fakehome" process-environment))))
    (should (equal "/tmp/fakehome/.local/state/emanix/welcome-dismissed"
                   (emanix-welcome--dismissed-file)))))

(ert-deftest emanix-welcome-config-repo-detects-a-flake ()
  "A directory holding flake.nix counts as a config repo; one without does not."
  (let* ((dir (make-temp-file "emanix-welcome-test" t)))
    (unwind-protect
        (progn
          (should-not (emanix-welcome--config-repo (list dir)))
          (write-region "" nil (expand-file-name "flake.nix" dir))
          (should (equal dir (emanix-welcome--config-repo (list dir)))))
      (delete-directory dir t))))

(ert-deftest emanix-welcome-config-repo-returns-the-first-hit ()
  "Candidates are tried in order, so a consumer's path wins over the generated one."
  (let* ((a (make-temp-file "emanix-welcome-a" t))
         (b (make-temp-file "emanix-welcome-b" t)))
    (unwind-protect
        (progn
          (write-region "" nil (expand-file-name "flake.nix" a))
          (write-region "" nil (expand-file-name "flake.nix" b))
          (should (equal a (emanix-welcome--config-repo (list a b)))))
      (delete-directory a t)
      (delete-directory b t))))

(ert-deftest emanix-welcome-renders-without-a-repo ()
  "With no config repo the buffer offers to create one."
  (let ((emanix-welcome-repo-candidates (list "/nonexistent-emanix-path")))
    (emanix-welcome)
    (with-current-buffer "*emanix-welcome*"
      (should (string-match-p "no config repo" (buffer-string)))
      (should (string-match-p "emanix.net" (buffer-string))))
    (kill-buffer "*emanix-welcome*")))

;;; emanix-welcome-test.el ends here
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
cd ioshi/i-intelligence/emacs && \
emacs --batch -Q -L lisp -L test -l ert -l test/emanix-welcome-test.el \
  -f ert-run-tests-batch-and-exit
```
Expected: FAIL — `Cannot open load file: emanix-welcome`.

- [ ] **Step 3: Write the module**

Create `ioshi/i-intelligence/emacs/lisp/emanix-welcome.el`:

```elisp
;;; emanix-welcome.el --- First-run orientation buffer -*- lexical-binding: t; -*-

;;; Commentary:
;; Shown once after an install.  Orientation, not documentation: the manual
;; lives at emanix.net and this buffer points there.
;;
;; Written under fallback.el's rule -- no package requires, no network -- because
;; it runs at startup and must never be the thing that breaks a first boot.
;;
;; Two facts are computed at RUNTIME, never baked in: whether this machine has
;; a config repo (false at first boot on a fresh install, true after
;; emanix-init) and where it is.  A hardcoded ~/dotfiles here would be the
;; emanix-elisa.el defect again -- shipped elisp naming a path that exists on
;; no machine.

;;; Code:

(defgroup emanix-welcome nil
  "First-run orientation buffer."
  :group 'emanix)

(defcustom emanix-welcome-repo-candidates
  (list (getenv "EMANIX_DOTFILES")
        (expand-file-name "flake" (or (getenv "HOME") "~"))
        "/etc/nixos")
  "Directories to search, in order, for this machine's config repo.
The first one containing a `flake.nix' wins.  Nil entries are ignored, so an
unset environment variable costs nothing."
  :type '(repeat (choice string (const nil))))

(defun emanix-welcome--dismissed-file ()
  "Return the path of the dismissal marker."
  (let* ((xdg (getenv "XDG_STATE_HOME"))
         (base (if (and xdg (not (string-empty-p xdg)))
                   xdg
                 (expand-file-name ".local/state" (or (getenv "HOME") "~")))))
    (expand-file-name "emanix/welcome-dismissed" base)))

(defun emanix-welcome--config-repo (&optional candidates)
  "Return the first directory in CANDIDATES holding a `flake.nix', or nil.
CANDIDATES defaults to `emanix-welcome-repo-candidates'."
  (seq-find (lambda (dir)
              (and dir
                   (file-directory-p dir)
                   (file-exists-p (expand-file-name "flake.nix" dir))))
            (delq nil (or candidates emanix-welcome-repo-candidates))))

(defvar-keymap emanix-welcome-mode-map
  :doc "Keymap for `emanix-welcome-mode'."
  "q" #'quit-window
  "n" #'emanix-welcome-never-again
  "i" #'emanix-welcome-init)

(define-derived-mode emanix-welcome-mode special-mode "Emanix-Welcome"
  "Major mode for the emanix orientation buffer.")

(defun emanix-welcome-never-again ()
  "Dismiss the welcome buffer permanently."
  (interactive)
  (let ((f (emanix-welcome--dismissed-file)))
    (make-directory (file-name-directory f) t)
    (write-region "" nil f nil 'quiet))
  (message "emanix: welcome dismissed. Reopen it any time with M-x emanix-welcome")
  (quit-window))

(defun emanix-welcome-init ()
  "Run `emanix-init' in a terminal-ish buffer to create a config repo."
  (interactive)
  (if (emanix-welcome--config-repo)
      (message "emanix: this machine already has a config repo")
    (if (executable-find "emanix-init")
        (async-shell-command "emanix-init" "*emanix-init*")
      (message "emanix: emanix-init is not on PATH"))))

;;;###autoload
(defun emanix-welcome ()
  "Show the emanix orientation buffer."
  (interactive)
  (let ((repo (emanix-welcome--config-repo))
        (buf (get-buffer-create "*emanix-welcome*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Emanix — Emacs is the desktop.\n\n")
        (insert "  s-<return>   terminal          C-c i   ask arc\n")
        (insert "  s-1 … s-9    frame slots       C-c t   ghostel\n")
        (insert "  s-d          app launcher      C-x g   magit\n")
        (insert "  s-arrows     move focus        C-c z   prose mode\n\n")
        (if repo
            (insert (format "  Your config    %s\n" repo))
          (insert "  ⚠ This machine has no config repo yet.\n")
          (insert "    Press [i] to create one you can edit and keep.\n"))
        (insert "  Manual         https://emanix.net\n\n")
        (insert "  [q] close   [n] never show again")
        (if repo "" "   [i] create a config repo")
        (insert "\n"))
      (emanix-welcome-mode)
      (goto-char (point-min)))
    (pop-to-buffer buf)))

;;;###autoload
(defun emanix-welcome-maybe-show ()
  "Show the welcome buffer unless it has been dismissed."
  (interactive)
  (unless (file-exists-p (emanix-welcome--dismissed-file))
    (emanix-welcome)))

(provide 'emanix-welcome)
;;; emanix-welcome.el ends here
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd ioshi/i-intelligence/emacs && \
emacs --batch -Q -L lisp -L test -l ert -l test/emanix-welcome-test.el \
  -f ert-run-tests-batch-and-exit
```
Expected: `Ran 5 tests, 5 results as expected`.

- [ ] **Step 5: Wire it into config.el**

In `ioshi/i-intelligence/emacs/config.el`, beside the other `lisp/` requires (near line 809, where `emanix-arc` is required):

```elisp
;; Orientation buffer, shown once per machine. `nil :no-error' like its
;; neighbours: a fault here must not cost the desktop.
(require 'emanix-welcome nil :no-error)
(when (fboundp 'emanix-welcome-maybe-show)
  (add-hook 'emacs-startup-hook #'emanix-welcome-maybe-show))
(when (fboundp 'emanix-welcome)
  (global-set-key (kbd "C-c ?") #'emanix-welcome))
```

- [ ] **Step 6: Verify the desktop still survives a broken config**

Run: `./tests/init-guard.sh`
Expected: PASS — proves the new require cannot take the desktop down.

- [ ] **Step 7: Commit**

```bash
git add ioshi/i-intelligence/emacs/lisp/emanix-welcome.el \
        ioshi/i-intelligence/emacs/test/emanix-welcome-test.el \
        ioshi/i-intelligence/emacs/config.el
git commit -m "emacs: a first-run orientation buffer

*emanix-welcome* on first start, dismissable with q (this session) or n
(permanently, via a marker under XDG_STATE_HOME), reopenable with C-c ? or
M-x emanix-welcome.

Orientation, not documentation -- ten lines and a pointer to emanix.net,
which is where the manual lives.

Two things are computed at runtime rather than baked in: whether this
machine has a config repo, and where. A hardcoded ~/dotfiles in shipped
elisp is the emanix-elisa.el defect, which named a path that existed on no
machine and went unnoticed for six weeks. When no repo is found the buffer
offers [i] to run emanix-init.

Written under fallback.el's rule -- no package requires, no network -- and
required with :no-error, so it cannot cost the desktop. tests/init-guard.sh
still passes."
```

---

### Task 5: `checks/welcome-keys.nix` — the drift guard

**Files:**
- Create: `checks/welcome-keys.nix`
- Modify: `flake.nix` (add `welcome-keys` to `checks.${system}`)

**Interfaces:**
- Consumes: `lisp/emanix-welcome.el` from Task 4.
- Produces: nothing.

- [ ] **Step 1: Write the check**

Create `checks/welcome-keys.nix`:

```nix
# The welcome buffer is the first thing a new user reads, so a key it
# advertises that does not exist is worse than no buffer at all.
#
# This guards the failure that actually happened to the docs: emanix.net
# published `elisa' for weeks after arc replaced it. Nothing detected it
# because nothing compared what the docs claimed against what the code did.
#
# It does NOT generate the buffer from the bindings, and deliberately so. Two
# thirds of the documented super-key surface is EWM upstream's keymap in the
# ewm input, not in this repo; fallback.el is a second, intentional definition
# site; and the manual's rows aggregate many bindings each while its prose
# explains rather than lists. Generation would have to discard all of that.
# Checking is cheap and loses nothing.
{ pkgs, ... }:
pkgs.runCommand "emanix-welcome-keys" { } ''
  welcome=${../ioshi/i-intelligence/emacs/lisp/emanix-welcome.el}
  config=${../ioshi/i-intelligence/emacs/config.el}
  fallback=${../ioshi/i-intelligence/emacs/fallback.el}

  # 1. No absolute home path. Same rule as arc-glue.nix, same reason.
  if grep -nE '"/home/[a-z]' "$welcome"; then
    echo "emanix-welcome.el contains an absolute home path; derive it from \$HOME" >&2
    exit 1
  fi

  # 2. The pre-rename name must not reappear.
  if grep -n 'eminix' "$welcome"; then
    echo "emanix-welcome.el mentions the pre-rename distro name; it is emanix now" >&2
    exit 1
  fi

  # 3. Every Emacs binding the buffer advertises must be bound somewhere in the
  #    shipped elisp. EWM's own super-keys are NOT checked here -- they live in
  #    the ewm input and this repo cannot see them -- so only C-* claims are
  #    verified, which is exactly the set this repo is responsible for.
  fails=0
  for key in $(grep -oE '"C-[a-z] [a-z?]"|C-c [a-z?]' "$welcome" \
               | tr -d '"' | sort -u); do
    if ! grep -qF "$key" "$config" && ! grep -qF "$key" "$fallback"; then
      echo "emanix-welcome.el advertises '$key' but nothing in config.el or fallback.el binds it" >&2
      fails=1
    fi
  done
  [ "$fails" -eq 0 ] || exit 1

  # 4. The buffer must still name the site. It is the only manual there is, and
  #    a welcome buffer that does not point at it orphans the reader.
  if ! grep -q 'emanix.net' "$welcome"; then
    echo "emanix-welcome.el no longer points at emanix.net" >&2
    exit 1
  fi

  # 5. The runtime probes must still be there. Replace either with a constant
  #    and the buffer starts telling a stranger about a path they do not have.
  for required in emanix-welcome--config-repo emanix-welcome--dismissed-file; do
    if ! grep -q "$required" "$welcome"; then
      echo "emanix-welcome.el no longer defines $required" >&2
      exit 1
    fi
  done

  touch $out
''
```

- [ ] **Step 2: Wire it into the flake**

Inside `checks.${system}`, beside `arc-glue`:

```nix
          # The welcome buffer's claims, checked against the bindings that
          # back them. See checks/welcome-keys.nix.
          welcome-keys = import ./checks/welcome-keys.nix { inherit pkgs; };
```

- [ ] **Step 3: Run it to verify it passes**

Run: `nix build --no-link .#checks.x86_64-linux.welcome-keys`
Expected: PASS.

- [ ] **Step 4: Prove it actually fails — do not skip this**

Temporarily add a line to `lisp/emanix-welcome.el`'s buffer text advertising a binding that does not exist:

```elisp
        (insert "  C-c j        does not exist\n")
```

Run: `nix build --no-link .#checks.x86_64-linux.welcome-keys`
Expected: FAIL with `advertises 'C-c j' but nothing in config.el or fallback.el binds it`.

Then remove that line and re-run:

Run: `nix build --no-link .#checks.x86_64-linux.welcome-keys`
Expected: PASS.

A guard that has never been observed failing is not a guard. `checks/arc-glue.nix` was written the same way.

- [ ] **Step 5: Run the whole check suite**

Run: `nix flake check`
Expected: `all checks passed!` — now 8 checks (`role-workstation`, `role-server`, `role-wsl`, `arc-glue`, `palette-contrast`, `template-host`, `welcome-keys`, and whatever else the tree carries).

- [ ] **Step 6: Commit**

```bash
git add checks/welcome-keys.nix flake.nix
git commit -m "checks: guard the welcome buffer's claims against the bindings

The failure this prevents is one that already happened to the docs:
emanix.net advertised 'elisa' for weeks after arc replaced it, because
nothing compared what the documentation claimed against what the code did.

Asserts that every C-* binding the buffer advertises is bound in config.el
or fallback.el, that it still points at emanix.net, that both runtime
probes still exist, and the arc-glue rules about absolute home paths and
the pre-rename name.

EWM's super-keys are deliberately NOT checked: they are defined in the ewm
flake input and this repo cannot see them. Verified to fail on a
deliberately wrong binding before being trusted."
```

---

## Self-Review

**Spec coverage:**

| Spec item | Task |
| --- | --- |
| `templates/default/` + `templates` output | 1 |
| Parameterized disko layout, in the template not `lib/` | 1 |
| CI builds the template's host | 1 |
| Mode detection by asking the flake | 2 |
| RFC 1123 hostname validation | 2, 3 |
| Known-host path unchanged, guarded by a test | 2 |
| Network handoff to `nmtui`/`iwctl` | 3 |
| Disk knob prompts | 3 |
| Fresh host key, agenix preflight skipped | 3 (installer generates the key; the fingerprint preflight is only reached on the pre-staged path) |
| `emanix-init` adopts and validates | 3 |
| `*emanix-welcome*`, `q`/`n`/`i`, XDG dismissal state | 4 |
| Runtime probes for repo presence and location | 4 |
| `fallback.el` discipline | 4 (verified by `tests/init-guard.sh`) |
| Generation rejected in favour of a drift check | 5 |
| `checks/welcome-keys.nix`, proven to fail | 5 |

**Gaps deliberately left, both from the spec's non-goals:** secrets provisioning for a generated host, and multi-disk/RAID/ZFS layouts.

**One spec item this plan does NOT cover:** the spec's verification plan asks for "a full interactive install into a VM, from a keyless ISO". That is an end-to-end manual test, not a task with a code deliverable — it should be run after Task 5 and before any of this is trusted on hardware. It is the only step that exercises `interactive_prompts` and `write_generated_flake` against a real disk, since nothing in `checks/` can wipe one.

**Type consistency:** `host.nix`'s five keys (`hostName`, `device`, `luks`, `filesystem`, `swapSize`) are written identically in Task 1's template, Task 1's check fixture, and Task 2/3's generator. `emanix-welcome--config-repo`, `emanix-welcome--dismissed-file` and `emanix-welcome-maybe-show` are named identically in Task 4's tests, Task 4's module, Task 4's config.el wiring, and Task 5's check.
