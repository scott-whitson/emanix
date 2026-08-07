# eminix IB Gateway NixOS Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace eminix's imperative IB Gateway install with a NixOS module so `ib up live` reliably brings up the gateway, pushes 2FA to Scott's phone, and opens port 4001.

**Architecture:** A single system module `ioshi/i-intelligence/ibgateway.nix` imported from `profiles/eminix.nix`, plus an IBC derivation at `ioshi/i-intelligence/ibgateway/ibc.nix`. IB Gateway itself stays an imperative payload in `/opt/ibgateway` so IBKR auto-updates keep working; everything around it — service account, directory ownership, JavaFX JDK, virtual display, config assembly, credentials, and the `ib` CLI — becomes declarative. The gateway runs as the `ibgateway` system user (fixing the permission fault) and is started manually, never at boot.

**Tech Stack:** NixOS modules, agenix, systemd, IBC 3.23.0, `openjdk17` with `enableJavaFX`, TigerVNC.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-06-eminix-ibgateway-module-design.md`
- Repo: `~/dotfiles` on eminix; deploy path is GitHub → datacore mirror → eminix pull, then `nixos-rebuild`
- **No `Co-Authored-By` trailers in any commit.**
- uid/gid **pinned**: `ibgateway` uid `993`, group gid `991` — matches on-disk ownership, avoids a recursive chown
- IB Gateway major version string: `1046`
- API port: `4001`. Display: `:50`. VNC port: `5901`, localhost-bound
- IBC 3.23.0 source hash: `sha256-C9A8cT8EwKZDZ6u9PVpA0ij8wvuWnJJ71829hbrdrEs=`
- JavaFX JDK: `pkgs.openjdk17.override { enableJavaFX = true; }` — verified distinct derivation, in cache.nixos.org, ships `javafx.web`
- The gateway unit is `wantedBy = [ ]` — **manual up/down only**, never boot-started
- `nixos-rebuild build` before any `switch`. Never switch blind.
- Do not commit any IBKR credential to git in plaintext

## Background the implementer needs

The current failure is **not** the JavaFX issue recorded in the old handoff note. IBC dies 1 ms after start with exit 1109 while writing `jts.ini`, because `/opt/ibgateway/jts` is `ibgateway:ibgateway 0755` and the service runs as `scott`. JavaFX is a real *second* cause that fires only once the first is cleared.

How IBC launches, verified against pristine 3.23.0:

- `gatewaystart.sh` sets ~14 env vars (all **hardcoded**, not env-overridable upstream) and execs `scripts/displaybannerandlaunch.sh`. It parses **no CLI arguments** except `-inline`.
- `displaybannerandlaunch.sh` reads those env vars, creates `$LOG_PATH`, and translates them into `scripts/ibcstart.sh` CLI arguments. It also traps `TERM`/`INT` and forwards to the JVM — needed for clean `systemctl stop`.
- `scripts/ibcstart.sh` takes CLI args (`--tws-path=`, `--ibc-path=`, `--ibc-ini=`, `--java-path=`, `--mode=`, `--on2fatimeout=`, …).

Therefore: we replace **only** `gatewaystart.sh` with a Nix-generated launcher that exports the same env vars pointing at store paths. `displaybannerandlaunch.sh` and `ibcstart.sh` ship pristine. Upstream explicitly marks the `gatewaystart.sh` variable block as the user-editable part.

Pristine `ibcstart.sh:495` already contains `--add-opens=javafx.graphics/…`, `--add-exports=javafx.media/…`, and `--add-exports=javafx.web/com.sun.javafx.webkit=ALL-UNNAMED`. Upstream assumes a JavaFX-bearing JDK. `ibcstart.sh:480` sets `JAVA_TOOL_OPTIONS=`, which is why the old `/tmp/javafx-sdk` workaround could never work. Supplying a JavaFX JDK via `--java-path` is the correct fix and needs no patching.

## File Structure

| File | Responsibility |
|---|---|
| `ioshi/i-intelligence/ibgateway/ibc.nix` | IBC 3.23.0 derivation. Fetch + unpack only. |
| `ioshi/i-intelligence/ibgateway.nix` | The module: options, user/group, tmpfiles, JDK, launcher, Xvnc unit, gateway unit, config assembly, polkit rule, `ib` CLI. |
| `secrets/secrets.nix` | Add `ibkr-creds.age` recipients. |
| `secrets/ibkr-creds.age` | Encrypted `IbLoginId=` / `IbPassword=`. |
| `profiles/eminix.nix` | Import the module. |
| `hosts/eminix/configuration.nix` | `scott.ibgateway.enable = true;` |

`ioshi/i-intelligence/default.nix` aggregates **Home Manager** modules only — do **not** add the module there.

---

### Task 1: IBC package derivation

**Files:**
- Create: `ioshi/i-intelligence/ibgateway/ibc.nix`

**Interfaces:**
- Produces: a derivation whose output contains `scripts/ibcstart.sh`, `scripts/displaybannerandlaunch.sh`, `IBC.jar`, and `version`. Later tasks reference it as `ibc` and use `${ibc}` as `IBC_PATH`.

- [ ] **Step 1: Write the verification check first**

Save as `/tmp/check-ibc.sh` (not committed):

```bash
#!/usr/bin/env bash
set -euo pipefail
OUT=$(nix build --no-link --print-out-paths \
  -f '<nixpkgs>' -E 'with import <nixpkgs> {}; callPackage /home/scott/dotfiles/ioshi/i-intelligence/ibgateway/ibc.nix {}' 2>&1 | tail -1)
echo "out=$OUT"
for f in scripts/ibcstart.sh scripts/displaybannerandlaunch.sh IBC.jar version; do
  [[ -e "$OUT/$f" ]] || { echo "MISSING: $f"; exit 1; }
done
[[ -x "$OUT/scripts/ibcstart.sh" ]] || { echo "NOT EXECUTABLE: ibcstart.sh"; exit 1; }
grep -q 'javafx.web/com.sun.javafx.webkit' "$OUT/scripts/ibcstart.sh" \
  || { echo "MISSING javafx.web add-exports — wrong IBC version"; exit 1; }
[[ "$(cat "$OUT/version")" == "3.23.0" ]] || { echo "WRONG VERSION"; exit 1; }
echo "IBC PACKAGE OK"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/check-ibc.sh`
Expected: FAIL — the file `ibc.nix` does not exist yet.

- [ ] **Step 3: Create the derivation**

```nix
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
```

- [ ] **Step 4: Run the check to verify it passes**

Run: `bash /tmp/check-ibc.sh`
Expected: `IBC PACKAGE OK`

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add ioshi/i-intelligence/ibgateway/ibc.nix
git commit -m "feat(ibgateway): package IBC 3.23.0

Ships pristine. Upstream gatewaystart.sh hardcodes its paths and parses no
CLI args, so the module supplies its own launcher rather than patching IBC."
```

---

### Task 2: Credentials secret

**Files:**
- Modify: `secrets/secrets.nix`
- Create: `secrets/ibkr-creds.age`

**Interfaces:**
- Produces: `config.age.secrets.ibkr-creds.path` — a file readable only by `ibgateway`, containing exactly two lines appended verbatim to the IBC config.

**Note:** run the `agenix` steps on **whistle** (the WSL work laptop), which holds the `swhitson-11l` private key that `secrets.nix` names as the `scott` recipient. eminix's user key is a *different* key and is not a recipient; editing there would need `sudo agenix -e -i /etc/ssh/ssh_host_ed25519_key`.

- [ ] **Step 1: Add the recipient entry**

In `secrets/secrets.nix`, inside the final attribute set, add below the existing line:

```nix
  "ibkr-creds.age".publicKeys = [ eminix scott ];
```

Only `eminix` and `scott` — no other host needs these credentials.

- [ ] **Step 2: Verify the rule is picked up and the secret is absent**

Run: `cd ~/dotfiles/secrets && nix run github:ryantm/agenix -- -e ibkr-creds.age --help >/dev/null 2>&1; ls ibkr-creds.age 2>&1`
Expected: `ls: cannot access 'ibkr-creds.age': No such file or directory`

- [ ] **Step 3: Create the encrypted secret**

```bash
cd ~/dotfiles/secrets
EDITOR="nano" nix run github:ryantm/agenix -- -e ibkr-creds.age
```

Enter exactly two lines, no comments, no trailing blank line beyond one newline:

```
IbLoginId=scottwhitson
IbPassword=<the current IBKR password>
```

These are appended verbatim to the generated IBC settings, so the key names must match IBC's spelling exactly.

- [ ] **Step 4: Verify it encrypted and decrypts**

Run: `cd ~/dotfiles/secrets && head -c 30 ibkr-creds.age && echo && nix run github:ryantm/agenix -- -d ibkr-creds.age | cut -d= -f1`
Expected: header begins `-----BEGIN AGE ENCRYPTED FILE`, and the field names print as `IbLoginId` and `IbPassword`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add secrets/secrets.nix secrets/ibkr-creds.age
git commit -m "feat(secrets): add ibkr-creds for IB Gateway

Credentials move out of the plaintext group-readable /etc/ibgateway/ibc-config.ini
into agenix. Only the two credential lines are encrypted; IBC settings stay in Nix."
```

---

### Task 3: Module skeleton — options, user, group, directories

**Files:**
- Create: `ioshi/i-intelligence/ibgateway.nix`
- Modify: `profiles/eminix.nix`
- Modify: `hosts/eminix/configuration.nix`

**Interfaces:**
- Consumes: `ibc.nix` from Task 1, `age.secrets.ibkr-creds` from Task 2
- Produces: options `scott.ibgateway.{enable,tradingMode,apiPort,display,vncPort,twsPath,twsMajorVersion}`; the `ibgateway` user (uid 993) and group (gid 991); tmpfiles rules guaranteeing `/opt/ibgateway/jts` is writable by that user

- [ ] **Step 1: Write the failing check**

Save as `/tmp/check-ibgw-users.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd ~/dotfiles
q() { nix eval --raw ".#nixosConfigurations.eminix.config.$1" 2>/dev/null; }

# /etc/passwd is generated at activation, not present in the built closure, so
# assert against the evaluated config rather than grepping result/etc/passwd.
[[ "$(q users.users.ibgateway.uid)" == "993" ]] || { echo "uid not pinned to 993"; exit 1; }
[[ "$(q users.groups.ibgateway.gid)" == "991" ]] || { echo "gid not pinned to 991"; exit 1; }
[[ "$(q users.users.ibgateway.group)" == "ibgateway" ]] || { echo "wrong primary group"; exit 1; }

nix eval --json '.#nixosConfigurations.eminix.config.systemd.tmpfiles.rules' \
  | grep -q '/opt/ibgateway/jts' || { echo "no tmpfiles rule for jts"; exit 1; }
nix eval --json '.#nixosConfigurations.eminix.config.users.users.scott.extraGroups' \
  | grep -q 'ibgateway' || { echo "scott not in ibgateway group"; exit 1; }
echo "USERS+DIRS OK"
```

`nix eval --raw` on an integer option prints the number; if the attribute does not exist the command errors and the comparison fails, which is the behaviour this check relies on.

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/check-ibgw-users.sh`
Expected: FAIL at `uid not pinned to 993` — nothing declares the account yet. It exists only imperatively in the live `/etc/passwd`, which is exactly why the evaluated config is the right thing to assert on.

- [ ] **Step 3: Create the module with options, user, and dirs**

Create `ioshi/i-intelligence/ibgateway.nix`:

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.scott.ibgateway;
in
{
  # IB Gateway + IBC as a NixOS system service (imported via profiles/eminix.nix,
  # like ewm.nix/secrets.nix/ollama.nix — NOT via i-intelligence/default.nix,
  # which aggregates Home Manager modules only).
  #
  # IB Gateway itself stays an imperative payload in /opt/ibgateway so IBKR's
  # forced auto-updates keep working. Everything around it is declarative.
  options.scott.ibgateway = {
    enable = lib.mkEnableOption "IB Gateway with IBC automation";

    tradingMode = lib.mkOption {
      type = lib.types.enum [ "live" "paper" ];
      default = "live";
      description = "IBC TradingMode.";
    };

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 4001;
      description = "TWS API port the gateway listens on (IBC OverrideTwsApiPort).";
    };

    display = lib.mkOption {
      type = lib.types.str;
      default = ":50";
      description = "X display for the headless gateway.";
    };

    vncPort = lib.mkOption {
      type = lib.types.port;
      default = 5901;
      description = "Xvnc RFB port. Bound to localhost only.";
    };

    twsPath = lib.mkOption {
      type = lib.types.path;
      default = "/opt/ibgateway/jts";
      description = ''
        IB Gateway install + settings dir. Imperative payload, not Nix-managed:
        IBKR's auto-updater rewrites it.
      '';
    };

    twsMajorVersion = lib.mkOption {
      type = lib.types.str;
      default = "1046";
      description = ''
        IB Gateway major version, no dot (10.46 -> 1046). Must match the
        directory under twsPath/ibgateway/. A forced IBKR upgrade needs this bumped.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # uid/gid pinned to what is already on disk so the existing /opt/ibgateway
    # files keep valid ownership across the switch — no recursive chown needed.
    users.groups.ibgateway.gid = 991;

    users.users.ibgateway = {
      isSystemUser = true;
      uid = 993;
      group = "ibgateway";
      home = "/var/lib/ibgateway";
      createHome = true;
      description = "IB Gateway service account";
    };

    # scott needs group membership to read gateway logs.
    users.users.scott.extraGroups = [ "ibgateway" ];

    # THE BUG FIX. IBC's first act is writing jts.ini into twsPath; when the
    # service ran as scott against an ibgateway-owned 0755 dir it died at 1ms
    # with exit 1109. These rules guarantee the service user can write there.
    systemd.tmpfiles.rules = [
      "d /opt/ibgateway          0755 ibgateway ibgateway -"
      "d ${cfg.twsPath}          0755 ibgateway ibgateway -"
      "d /var/lib/ibgateway      0750 ibgateway ibgateway -"
      "d /var/lib/ibgateway/ibc  0750 ibgateway ibgateway -"
      "d /var/lib/ibgateway/ibc/logs 0750 ibgateway ibgateway -"
    ];
  };
}
```

- [ ] **Step 4: Import the module and enable it**

In `profiles/eminix.nix`, add to the `imports` list after `../ioshi/i-intelligence/ollama.nix`:

```nix
    ../ioshi/i-intelligence/ibgateway.nix
```

In `hosts/eminix/configuration.nix`, add before the closing brace:

```nix
  # IB Gateway — manual up/down via `ib up live`, never started at boot.
  scott.ibgateway.enable = true;
```

- [ ] **Step 5: Run the check to verify it passes**

Run: `bash /tmp/check-ibgw-users.sh`
Expected: `USERS+DIRS OK`

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles
git add ioshi/i-intelligence/ibgateway.nix profiles/eminix.nix hosts/eminix/configuration.nix
git commit -m "feat(ibgateway): module skeleton with pinned service account

uid 993 / gid 991 match the existing imperative account so /opt ownership
survives the switch. tmpfiles rules guarantee the service user can write
jts.ini — the exit-1109 fault."
```

---

### Task 4: Xvnc display service

**Files:**
- Modify: `ioshi/i-intelligence/ibgateway.nix`

**Interfaces:**
- Produces: `ibgateway-xvnc.service`, an X server on `cfg.display` owned by `ibgateway`, RFB on `cfg.vncPort` bound to localhost. The gateway unit will `Requires=`/`After=` it.

- [ ] **Step 1: Write the failing check**

Save as `/tmp/check-ibgw-xvnc.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd ~/dotfiles
nixos-rebuild build --flake .#eminix
U=result/etc/systemd/system/ibgateway-xvnc.service
[[ -f "$U" ]] || { echo "unit not generated"; exit 1; }
grep -q 'User=ibgateway'  "$U" || { echo "wrong user"; exit 1; }
grep -q -- '-localhost'   "$U" || { echo "VNC not localhost-bound"; exit 1; }
grep -q -- '-rfbport 5901' "$U" || { echo "wrong rfb port"; exit 1; }
grep -qE 'ExecStart=.*/Xvnc :50' "$U" || { echo "wrong display"; exit 1; }
echo "XVNC UNIT OK"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/check-ibgw-xvnc.sh`
Expected: FAIL — `unit not generated`.

- [ ] **Step 3: Add the Xvnc service**

Inside the `config = lib.mkIf cfg.enable { ... }` block, after `systemd.tmpfiles.rules`:

```nix
    # Headless X for the gateway. Xvnc rather than Xvfb: identical behaviour
    # when IBC drives the login, but keeps a viewer escape hatch when it does
    # not. -localhost keeps the RFB port off the tailnet.
    #
    # Declaring this as a unit is what stops the old :50-vs-:99 mismatch
    # recurring: previously the start script used :50 (a stray unmanaged Xvnc)
    # while the unit depended on xvfb.service on :99.
    systemd.services.ibgateway-xvnc = {
      description = "Xvnc virtual display for IB Gateway";
      wantedBy = [ ];  # started as a dependency of ibgateway.service
      serviceConfig = {
        Type = "simple";
        User = "ibgateway";
        Group = "ibgateway";
        StateDirectory = "ibgateway";
        Environment = [ "HOME=/var/lib/ibgateway" ];
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.tigervnc}/bin/Xvnc"
          cfg.display
          "-geometry 1280x1024"
          "-depth 24"
          "-SecurityTypes=None"
          "-rfbport ${toString cfg.vncPort}"
          "-localhost"
        ];
        Restart = "always";
        RestartSec = 5;
      };
    };
```

`-SecurityTypes=None` uses the `=` form, matching the invocation already proven working on this box.

- [ ] **Step 4: Run the check to verify it passes**

Run: `bash /tmp/check-ibgw-xvnc.sh`
Expected: `XVNC UNIT OK`

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add ioshi/i-intelligence/ibgateway.nix
git commit -m "feat(ibgateway): declare localhost-bound Xvnc display

Replaces the stray unmanaged Xvnc :50 process and removes the :50/:99
mismatch that would break the gateway on any reboot."
```

---

### Task 5: Launcher, config assembly, and the gateway service

**Files:**
- Modify: `ioshi/i-intelligence/ibgateway.nix`

**Interfaces:**
- Consumes: `ibc` (Task 1), `age.secrets.ibkr-creds` (Task 2), `ibgateway-xvnc.service` (Task 4)
- Produces: `ibgateway.service` — manual-start, capped restarts, assembling `/run/ibgateway/ibc-config.ini` at `0400 ibgateway` before launch

- [ ] **Step 1: Write the failing check**

Save as `/tmp/check-ibgw-service.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd ~/dotfiles
nixos-rebuild build --flake .#eminix
U=result/etc/systemd/system/ibgateway.service
[[ -f "$U" ]] || { echo "unit not generated"; exit 1; }
grep -q 'User=ibgateway'                "$U" || { echo "wrong user"; exit 1; }
grep -q 'Requires=ibgateway-xvnc'       "$U" || { echo "missing xvnc dep"; exit 1; }
grep -q 'StartLimitBurst=5'             "$U" || { echo "NO RESTART CAP"; exit 1; }
grep -q 'RuntimeDirectory=ibgateway'    "$U" || { echo "no runtime dir"; exit 1; }
grep -q 'DISPLAY=:50'                   "$U" || { echo "display not set"; exit 1; }
# Must NOT be boot-enabled.
if grep -rq 'ibgateway.service' result/etc/systemd/system/multi-user.target.wants/ 2>/dev/null; then
  echo "REGRESSION: gateway is boot-enabled"; exit 1
fi
# The launcher must point java at a JavaFX-bearing JDK.
LAUNCH=$(grep -oE '/nix/store/[a-z0-9]+-ibgateway-launcher[^ "]*' "$U" | head -1)
grep -q 'JAVA_PATH=' "$LAUNCH" || { echo "launcher sets no JAVA_PATH"; exit 1; }
JDK=$(grep -oE 'JAVA_PATH=[^ ]*' "$LAUNCH" | cut -d= -f2 | tr -d '"')
"${JDK}/java" --list-modules | grep -q javafx.web || { echo "JDK LACKS javafx.web"; exit 1; }
echo "GATEWAY UNIT OK"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/check-ibgw-service.sh`
Expected: FAIL — `unit not generated`.

- [ ] **Step 3: Add the let-bindings**

Extend the `let` block at the top of the module so it reads:

```nix
let
  cfg = config.scott.ibgateway;

  ibc = pkgs.callPackage ./ibgateway/ibc.nix { };

  # Zulu (the old choice) has no JavaFX, and IBC's login dialog is a JavaFX
  # WebView. Pristine ibcstart.sh already passes --add-exports for javafx.web,
  # so it assumes a JavaFX-bearing JDK — this override supplies exactly that.
  # It is a distinct derivation from plain openjdk17 and is in cache.nixos.org.
  #
  # The old /tmp/javafx-sdk + JAVA_TOOL_OPTIONS workaround could never work:
  # ibcstart.sh:480 clears JAVA_TOOL_OPTIONS unconditionally.
  jdk = pkgs.openjdk17.override { enableJavaFX = true; };

  # Non-secret IBC settings. Credentials are appended at runtime from agenix,
  # so nothing here reaches the world-readable Nix store.
  ibcSettings = pkgs.writeText "ibc-settings.ini" ''
    TradingMode=${cfg.tradingMode}
    IbDir=${cfg.twsPath}
    OverrideTwsApiPort=${toString cfg.apiPort}
    AcceptIncomingConnectionAction=accept
    AcceptNonBrokerageAccountWarning=yes
    ExistingSessionDetectedAction=primary
    ReloginAfterSecondFactorAuthenticationTimeout=yes
    BypassOrderPrecautions=yes
    SecondFactorAuthenticationModule=2
    SecondFactorAuthenticationTimeout=120
    CommandServerPort=7462
    ControlFrom=127.0.0.1
  '';

  runtimeIni = "/run/ibgateway/ibc-config.ini";

  # Stands in for IBC's gatewaystart.sh, whose variable block upstream hardcodes
  # and marks as the user-editable part. displaybannerandlaunch.sh and
  # ibcstart.sh ship pristine; this only supplies the env they read.
  launcher = pkgs.writeShellApplication {
    name = "ibgateway-launcher";
    runtimeInputs = [ pkgs.coreutils pkgs.procps pkgs.gnugrep pkgs.gawk ];
    text = ''
      export IBC_PATH=${ibc}
      export IBC_INI=${runtimeIni}
      export TWS_PATH=${cfg.twsPath}
      export TWS_SETTINGS_PATH=${cfg.twsPath}
      export TWS_MAJOR_VRSN=${cfg.twsMajorVersion}
      export LOG_PATH=/var/lib/ibgateway/ibc/logs
      export JAVA_PATH=${jdk}/bin
      export TRADING_MODE=${cfg.tradingMode}
      export TWOFA_TIMEOUT_ACTION=restart
      export APP=GATEWAY
      # Credentials come from the ini, not these. displaybannerandlaunch.sh
      # dereferences them unconditionally, so they must exist.
      export TWSUSERID=""
      export TWSPASSWORD=""
      export FIXUSERID=""
      export FIXPASSWORD=""
      exec ${ibc}/scripts/displaybannerandlaunch.sh
    '';
  };

  # Fails fast with a named cause instead of a bare exit 1109.
  preflight = pkgs.writeShellScript "ibgateway-preflight" ''
    set -euo pipefail
    creds=${config.age.secrets.ibkr-creds.path}

    if [[ ! -s "$creds" ]]; then
      echo "ibgateway: credentials $creds missing or empty" >&2
      exit 1
    fi
    if [[ ! -d "${cfg.twsPath}/ibgateway/${cfg.twsMajorVersion}/jars" ]]; then
      echo "ibgateway: no jars at ${cfg.twsPath}/ibgateway/${cfg.twsMajorVersion}/jars —" \
           "IB Gateway may have auto-updated; bump scott.ibgateway.twsMajorVersion" >&2
      exit 1
    fi
    if [[ ! -w "${cfg.twsPath}" ]]; then
      echo "ibgateway: ${cfg.twsPath} not writable by $(id -un) —" \
           "this is the condition that produced the silent exit 1109" >&2
      exit 1
    fi

    umask 077
    cat ${ibcSettings} "$creds" > ${runtimeIni}
    chmod 0400 ${runtimeIni}
  '';
in
```

- [ ] **Step 4: Add the agenix secret and the gateway service**

Inside `config = lib.mkIf cfg.enable { ... }`, after the Xvnc service:

```nix
    age.secrets.ibkr-creds = {
      file = ../../secrets/ibkr-creds.age;
      owner = "ibgateway";
      group = "ibgateway";
      mode = "0400";
    };

    systemd.services.ibgateway = {
      description = "IB Gateway (IBC-managed)";
      requires = [ "ibgateway-xvnc.service" ];
      after = [ "ibgateway-xvnc.service" "network-online.target" ];
      wants = [ "network-online.target" ];

      # Manual up/down only. Boot-starting would fire an unattended IBKR
      # authentication and push 2FA to Scott's phone on every startup.
      wantedBy = [ ];

      environment = {
        DISPLAY = cfg.display;
        HOME = "/var/lib/ibgateway";
      };

      serviceConfig = {
        Type = "simple";
        User = "ibgateway";
        Group = "ibgateway";
        RuntimeDirectory = "ibgateway";
        RuntimeDirectoryMode = "0700";
        StateDirectory = "ibgateway";
        ExecStartPre = preflight;
        ExecStart = "${launcher}/bin/ibgateway-launcher";
        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStartSec = 660;
      };

      # The old unit had Restart=on-failure with NO cap and reached 4085
      # restarts, silently hammering IBKR auth with a broken config.
      startLimitBurst = 5;
      startLimitIntervalSec = 300;
    };
```

- [ ] **Step 5: Run the check to verify it passes**

Run: `bash /tmp/check-ibgw-service.sh`
Expected: `GATEWAY UNIT OK`

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles
git add ioshi/i-intelligence/ibgateway.nix
git commit -m "feat(ibgateway): gateway service, JavaFX JDK, config assembly

Runs as ibgateway so jts.ini writes succeed. openjdk17 with enableJavaFX
replaces Zulu — pristine ibcstart.sh already assumes a JavaFX JDK and clears
JAVA_TOOL_OPTIONS, so the old /tmp module-path hack was unfixable.
Credentials assembled into /run at 0400. Restart capped at 5/300s."
```

---

### Task 6: `ib` CLI and polkit rule

**Files:**
- Modify: `ioshi/i-intelligence/ibgateway.nix`
- Delete: `base/bin/ib`
- Delete: `bin/ib`

**Interfaces:**
- Consumes: `ibgateway.service`, `ibgateway-xvnc.service`
- Produces: `ib` on `PATH` system-wide via `environment.systemPackages`, with `up` / `down` / `status`

- [ ] **Step 1: Write the failing check**

Save as `/tmp/check-ibgw-cli.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd ~/dotfiles
nixos-rebuild build --flake .#eminix
IB=$(find result/sw/bin -name ib -maxdepth 1 2>/dev/null | head -1)
[[ -n "$IB" ]] || { echo "ib not in systemPackages"; exit 1; }
grep -q 'systemctl start ibgateway'   "$IB" || { echo "does not start system unit"; exit 1; }
grep -q 'ibgateway-xvnc'              "$IB" || { echo "down does not stop xvnc"; exit 1; }
grep -q 'systemctl --user'            "$IB" || { echo "does not drive minne user units"; exit 1; }
grep -rq 'ibgateway.service' result/etc/polkit-1/ 2>/dev/null \
  || { echo "no polkit rule"; exit 1; }
echo "IB CLI OK"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/check-ibgw-cli.sh`
Expected: FAIL — `ib not in systemPackages` (today `ib` is only a loose script in `~/dotfiles/bin`).

- [ ] **Step 3: Add the CLI to the `let` block**

Append inside the existing `let` block, after `preflight`:

```nix
  ibCli = pkgs.writeShellApplication {
    name = "ib";
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      # ib — IB Gateway control. The gateway is a SYSTEM unit (runs as the
      # ibgateway user); a polkit rule lets scott manage it without a password.
      # Minne remains user units.
      action="''${1:-status}"
      mode="''${2:-${cfg.tradingMode}}"

      gateway_ready() {
        timeout 1 bash -c ">/dev/tcp/127.0.0.1/${toString cfg.apiPort}" 2>/dev/null
      }

      case "$action" in
        up)
          echo "Starting IB Gateway ($mode)..."
          systemctl start ibgateway.service

          for _ in $(seq 1 120); do
            if gateway_ready; then
              echo "IB Gateway ready on port ${toString cfg.apiPort}"
              systemctl --user start minne-ibkr-gateway minne-ibkr-record
              echo "Minne IBKR services started"
              exit 0
            fi
            if ! systemctl is-active --quiet ibgateway.service; then
              echo "ERROR: ibgateway.service died. Recent log:" >&2
              journalctl -u ibgateway.service -n 30 --no-pager >&2
              exit 1
            fi
            sleep 1
          done

          echo "WARNING: gateway did not open port ${toString cfg.apiPort} within 120s" >&2
          echo "Approve the 2FA push on your phone, or attach a viewer:" >&2
          echo "  vncviewer localhost:${toString cfg.vncPort}" >&2
          exit 1
          ;;

        down)
          echo "Stopping IB Gateway ($mode)..."
          systemctl --user stop minne-ibkr-record minne-ibkr-gateway 2>/dev/null || true
          systemctl stop ibgateway.service ibgateway-xvnc.service
          echo "IB Gateway stopped"
          ;;

        status)
          echo "=== IB Gateway ==="
          systemctl is-active ibgateway.service || true
          echo "=== Display ==="
          systemctl is-active ibgateway-xvnc.service || true
          echo "=== Port ${toString cfg.apiPort} ==="
          if gateway_ready; then echo open; else echo closed; fi
          echo "=== Minne IBKR ==="
          systemctl --user is-active minne-ibkr-gateway minne-ibkr-record || true
          ;;

        *)
          echo "Usage: ib {up|down|status} [live|paper]" >&2
          exit 1
          ;;
      esac
    '';
  };
```

Two behaviour changes from the old script: `up` now aborts early with the journal tail when the unit dies rather than waiting the full 120 s, and `down` stops the display too, so a manual `down` leaves nothing running.

- [ ] **Step 4: Register the CLI and polkit rule**

Inside `config = lib.mkIf cfg.enable { ... }`, after the gateway service:

```nix
    environment.systemPackages = [ ibCli ];

    # Let scott manage just these two units without a password. Narrower than
    # a sudo rule: it grants nothing else, to nobody else.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            subject.user == "scott") {
          var unit = action.lookup("unit");
          if (unit == "ibgateway.service" || unit == "ibgateway-xvnc.service") {
            return polkit.Result.YES;
          }
        }
      });
    '';
```

- [ ] **Step 5: Remove the superseded scripts**

```bash
cd ~/dotfiles
git rm base/bin/ib bin/ib
```

`base/bin/ib` was a stray duplicate that would stow to `~/ib` (it never was stowed). `bin/ib` is superseded by the packaged CLI.

- [ ] **Step 6: Run the check to verify it passes**

Run: `bash /tmp/check-ibgw-cli.sh`
Expected: `IB CLI OK`

- [ ] **Step 7: Commit**

```bash
cd ~/dotfiles
git add ioshi/i-intelligence/ibgateway.nix
git commit -m "feat(ibgateway): package ib CLI, drop loose scripts

ib becomes a system package driving the system unit via a polkit rule scoped
to ibgateway{,-xvnc}.service. up now fails fast with the journal tail when
the unit dies; down stops the display too. Removes the base/bin/ib duplicate."
```

---

### Task 7: Deploy and verify live

**Files:** none — deployment and verification only.

This is the task that proves the fix. It ends with a real IBKR login and a 2FA push to Scott's phone, so **confirm he is ready before Step 4.**

- [ ] **Step 1: Push through the three-hop path**

```bash
cd ~/dotfiles && git push
ssh datacore 'cd ~/dotfiles && git fetch origin && git merge --ff-only origin/main'
ssh eminix   'cd ~/dotfiles && git pull'
```

- [ ] **Step 2: Build before switching**

Run: `ssh eminix 'cd ~/dotfiles && nixos-rebuild build --flake .#eminix'`
Expected: builds clean. **Do not switch if this fails.**

- [ ] **Step 3: Stop the old imperative units, then switch**

```bash
ssh eminix 'systemctl --user disable --now ibgateway.service xvfb.service 2>/dev/null || true
            pkill -f "Xvnc :50" || true
            cd ~/dotfiles && sudo nixos-rebuild switch --flake .#eminix'
```

Stopping first avoids the old user unit and the new system unit contending for display `:50` and port 4001.

- [ ] **Step 4: Verify the permission fault is gone (no login yet)**

```bash
ssh eminix 'sudo systemctl start ibgateway.service; sleep 20
            systemctl status ibgateway.service --no-pager | head -20
            ls -la /opt/ibgateway/jts/jts.ini
            tail -30 /var/lib/ibgateway/ibc/logs/ibc-3.23.0_GATEWAY-1046_*.txt'
```

Expected, and each is a distinct pass condition:
- unit is `active (running)`, **not** looping
- `/opt/ibgateway/jts/jts.ini` **exists** — previously impossible
- the IBC log passes `Creating minimal ... jts.ini` **without** `Exiting with exit code=1109`
- the log reaches `Starting session: will exit if login dialog is not displayed within 60 seconds` and **waits** rather than exiting in 1 ms

- [ ] **Step 5: Verify JavaFX loaded**

Run: `ssh eminix 'grep -c "javafx.scene.Parent" /var/lib/ibgateway/Jts/launcher.log 2>/dev/null || echo 0'`
Expected: `0` — no `ClassNotFoundException: javafx.scene.Parent`. A non-zero count means the JDK swap did not take effect; stop and re-check `JAVA_PATH` in the launcher.

- [ ] **Step 6: Live 2FA test — confirm Scott has his phone ready**

Run, in a terminal on eminix: `ib up live`

Expected sequence: IBC submits credentials → **2FA push arrives on the phone** → Scott approves → port 4001 opens → Minne services start → `ib` exits 0 with `IB Gateway ready on port 4001`.

If the push never arrives, attach a viewer to see the dialog state: `vncviewer localhost:5901`

- [ ] **Step 7: Verify status and clean shutdown**

```bash
ssh eminix 'ib status'    # gateway active, display active, port open, minne active
ssh eminix 'ib down'
ssh eminix 'ib status'    # all inactive, port closed
```

- [ ] **Step 8: Reboot durability test**

```bash
ssh eminix 'sudo reboot'
# wait for it to come back
ssh eminix 'ib status'
```

Expected: gateway and display both **inactive** (correct — manual start only), and no `/tmp` dependency remains. Then `ib up live` must work again from cold. This is the property the old setup never had.

- [ ] **Step 9: Commit nothing; record the result**

No code changes. If any step failed, return to the relevant task rather than patching live on the box.

---

### Task 8: Remove the imperative leftovers

Only after Task 7 passes end to end.

**Files:**
- Delete on eminix (not in the repo): the old scripts, units, and SDK

- [ ] **Step 1: Verify the new stack is the one in use**

```bash
ssh eminix 'systemctl cat ibgateway.service | head -3
            ib up live && ib status && ib down'
```

Expected: unit path is `/etc/systemd/system/ibgateway.service` (system, Nix-generated), not `/home/scott/.config/systemd/user/...`, and the cycle succeeds.

- [ ] **Step 2: Remove the superseded artifacts**

```bash
ssh eminix 'rm -f ~/bin/ibgateway-start.sh ~/bin/ibgateway-fhs
            rm -f ~/.config/systemd/user/ibgateway.service ~/.config/systemd/user/xvfb.service
            systemctl --user daemon-reload
            rm -rf /tmp/javafx-sdk /tmp/ibc-pristine'
```

- [ ] **Step 3: Retire the plaintext credentials file**

```bash
ssh eminix 'sudo rm -f /etc/ibgateway/ibc-config.ini && sudo rmdir /etc/ibgateway 2>/dev/null || true'
```

The credentials now live in agenix and are assembled into `/run/ibgateway/ibc-config.ini` at `0400`.

- [ ] **Step 4: Remove the old IBC tree**

```bash
ssh eminix 'sudo rm -rf /opt/ibc'
```

Safe because the service points at the store path. `/opt/ibgateway` **stays** — that is the IB Gateway payload.

- [ ] **Step 5: Confirm nothing broke**

Run: `ssh eminix 'ib up live && ib status && ib down'`
Expected: full cycle still succeeds with the old tree gone.

- [ ] **Step 6: Update the handoff note**

Rewrite `~/docs/Hobbies/Forex Trading/Minne/eminix-ibgateway-debug.md` to point at the spec and record the corrected root cause — the permission fault, not JavaFX alone — so the stale JavaFX-only diagnosis does not mislead a future session.

- [ ] **Step 7: Commit the note**

```bash
cd ~/docs && git add "Hobbies/Forex Trading/Minne/eminix-ibgateway-debug.md"
git commit -m "docs(minne): supersede IB Gateway debug note with NixOS module"
```

---

## Follow-ups, explicitly out of scope

Recorded so they are not silently lost:

- **Rotate the IBKR password.** It sat in cleartext in a `0640 ibgateway:users` file and was visible during diagnosis.
- **Suspend/resume.** eminix is a T14; the gateway will still lose or wedge its session across suspend. A `systemd-sleep` hook is the fix if it proves annoying.
- **Minne user units** remain hand-written in `~/.config/systemd/user/`; a fresh install will not recreate them.
- **Readiness/heartbeat wrapper** like datacore's `ibgateway-launcher` was not ported.
- **IB Gateway auto-update** will eventually force 10.47; bump `scott.ibgateway.twsMajorVersion`. Task 5's preflight names this explicitly when the jars path goes missing.
