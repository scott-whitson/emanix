# eminix IB Gateway NixOS module — design

**Date:** 2026-08-06
**Status:** approved (design), pending implementation
**Context:** `ib up live` on eminix has been non-functional. The prior handoff note
(`~/docs/Hobbies/Forex Trading/Minne/eminix-ibgateway-debug.md`) diagnosed the failure as
JavaFX modules missing from Zulu JDK 17. That diagnosis described a real but *earlier*
failure; the box has since regressed to a different, earlier-firing fault. This spec
replaces the whole imperative install with a NixOS module.

## Problem

### Observed failure (2026-08-06)

`ibgateway.service` (user service) was in an uncapped crash-restart loop — **restart
counter 4085** — and was stopped during diagnosis. The IBC diagnostic log shows:

```
21:33:42:561 IBC: Starting session: will exit if login dialog is not displayed within 60 seconds
21:33:42:562 IBC: Creating minimal /opt/ibgateway/jts/jts.ini
21:33:42:563 IBC: Exiting with exit code=1109
```

**Elapsed: 1 millisecond, not 60 seconds.** IBC never waits for a dialog, never starts a
JVM GUI, never reaches JavaFX. It dies writing `jts.ini`. Confirmed directly:

```
$ touch /opt/ibgateway/jts/_writetest
touch: cannot touch '/opt/ibgateway/jts/_writetest': Permission denied
```

`/opt/ibgateway/jts` is `ibgateway:ibgateway 0755` and contains no `jts.ini`. The user
service runs as `scott`, who is in the `ibgateway` *group* — but group perms are `r-x`.
On datacore (working reference) the equivalent service runs `User=ibgateway` and
`jts.ini` exists, owned by that user.

### Root causes, in firing order

1. **Permission (blocking).** Service runs as `scott`; settings dir is writable only by
   `ibgateway`. Fires at 1 ms, exit 1109.
2. **JavaFX (latent, fires once #1 clears).** Zulu 17 has no JavaFX modules. The current
   workaround cannot ever work: `JAVA_TOOL_OPTIONS` points at `/tmp/javafx-sdk/...`
   (`/tmp`, wiped on reboot), and IBC's `ibcstart.sh` explicitly clears
   `JAVA_TOOL_OPTIONS`.
3. **Display mismatch.** `~/bin/ibgateway-start.sh` exports `DISPLAY=:50` (Xvnc) but the
   unit only `Requires=xvfb.service` (`:99`). Xvnc `:50` is a stray unmanaged process
   (was PID 18746), so this breaks on any reboot regardless of #1 and #2.
4. **No restart cap.** `Restart=on-failure` with no `StartLimit*` produced the 4085-restart
   loop, silently retrying against IBKR auth with a broken config.

### Corrected non-finding

`ib` **is** on PATH — `~/dotfiles/bin/ib`, via `$DOTFILES/bin` exported in
`ioshi/i-intelligence/zsh.nix` `initContent`. An early check using `bash -lc` did not load
the zsh config and wrongly suggested otherwise. The command runs; the service under it was
dead. `~/dotfiles/base/bin/ib` is a stray duplicate (would stow to `~/ib`, which does not
exist).

### Undeclared surface

Nothing IB-related is in the flake today:

| Artifact | State |
|---|---|
| `/opt/ibgateway/` (10.46) | install4j blob, `jts/` owned `ibgateway:ibgateway` |
| `/opt/ibc/` (3.23.0) | **hand-edited `ibcstart.sh`** (`--module-path` hack, applied via sudo) |
| `/etc/ibgateway/ibc-config.ini` | plaintext IBKR password, `0640 ibgateway:users` |
| `ibgateway` user (uid 993, gid 991) | created imperatively, persists via `mutableUsers` |
| `~/.config/systemd/user/{ibgateway,xvfb}.service` | hand-written, not in repo |
| `~/bin/ibgateway-start.sh`, `~/bin/ibgateway-fhs` | not in repo |
| `/tmp/javafx-sdk/` | ephemeral |
| `Xvnc :50` | stray process |

Neither IB Gateway nor IBC is packaged in nixpkgs (probed: `ib-tws`, `ibgateway`,
`ib-gateway`, `tws`, `interactive-brokers-tws`, `ibc`, `trader-workstation` — all missing).

## Verified facts

Established empirically during design, not assumed:

- `pkgs.openjdk17.override { enableJavaFX = true; }` is a **distinct derivation**
  (`fvngmv7...-openjdk-17.0.20+2` vs plain `q6zvjln...`), so the override is not a no-op.
- It is **present in cache.nixos.org** — no multi-hour source build on the T14.
- Its `java --list-modules` reports all seven JavaFX modules, including **`javafx.web`**,
  the module IB Gateway's JxBrowser/WebView login dialog requires.
- `pkgs.tigervnc` is `tigervnc-1.16.2`.

This replaces the BellSoft-Java-17-Full approach datacore uses, with no module path, no
`/tmp` SDK, and nothing for `ibcstart.sh` to strip.

## Design

### Decisions taken

| Question | Decision |
|---|---|
| Packaging scope | Package IBC; keep IB Gateway imperative in `/opt` so it can self-update |
| Service user | System service as `ibgateway` (matches datacore) |
| Secrets | Non-secret settings in Nix; credentials in agenix; assembled at runtime |
| Display | Xvnc only, localhost-bound |
| Extra scope | `ib` CLI becomes a Nix package. Minne units, readiness/heartbeat wrapper, and suspend hooks are **out of scope** |

### 1. Module shape and placement

New system module `ioshi/i-intelligence/ibgateway.nix`, imported from
`profiles/eminix.nix` alongside `ewm.nix` / `secrets.nix` / `ollama.nix`.

`ioshi/i-intelligence/default.nix` aggregates only the Home Manager modules — a system
module must **not** be added there.

Options namespace `scott.ibgateway`, following the existing `scott.*` convention:
`enable`, `tradingMode`, `apiPort`, `display`, `vncPort`. Body under `lib.mkIf`, defaults
off, so only eminix opts in.

Supporting file: `ioshi/i-intelligence/ibgateway/ibc.nix`.

### 2. IBC package

`stdenv.mkDerivation` fetching the IBC 3.23.0 release zip, unpacked into the store.

**IBC ships unmodified.** The `--module-path` edit to `ibcstart.sh` exists only to inject
JavaFX; with a JavaFX-enabled JDK it is unnecessary. The sudo-edited script is therefore
retired outright rather than reproduced — the hack stops being an undocumented on-disk
mutation that a reinstall would silently lose. `substituteInPlace` is available at build
time if a concrete need surfaces during implementation, but none is anticipated; any such
patch must be justified in the plan rather than added speculatively.

IB Gateway itself stays in `/opt/ibgateway` as an imperative payload, so IBKR's forced
auto-updates keep working.

### 3. User, group, and state dirs

- `users.groups.ibgateway.gid = 991`
- `users.users.ibgateway` — `isSystemUser`, `group = "ibgateway"`, `uid = 993`,
  `home = /var/lib/ibgateway`
- `scott` added to the `ibgateway` group

**uid/gid are pinned to the values already on disk** (993/991) so existing `/opt` files
keep valid ownership through the switch, avoiding a recursive chown.

`systemd.tmpfiles.rules` assert ownership on `/opt/ibgateway`, `/opt/ibgateway/jts`, and
`/var/lib/ibgateway`. **This is the fix for root cause #1** — it guarantees the service
user can write `jts.ini`.

### 4. Display

`systemd.services.ibgateway-xvnc`: TigerVNC `Xvnc :50 -geometry 1280x1024 -depth 24
-rfbport 5901 -localhost`, `User=ibgateway`.

`-localhost` keeps the VNC port off the tailnet. The gateway unit `Requires=` and
`After=` this service, so the `:50`/`:99` mismatch (root cause #3) cannot recur.

Xvnc rather than Xvfb: identical headless behaviour when IBC drives the login, plus a
viewer escape hatch for when it does not — which is how the session was recovered
previously.

### 5. Gateway service

`systemd.services.ibgateway`:

- `User` / `Group` = `ibgateway`
- `RuntimeDirectory=ibgateway` (gives `/run/ibgateway`, 0700, auto-cleaned)
- `Requires` / `After` = `ibgateway-xvnc.service`
- `Environment`: `DISPLAY=:50`, `IBC_PATH`, `TWS_PATH=/opt/ibgateway/jts`,
  `JAVA_PATH` → JavaFX JDK `bin`
- `ExecStartPre`: config assembly + preflight validation (§6, §7)
- `ExecStart`: IBC `gatewaystart.sh -inline`
- `Restart=on-failure`, `RestartSec=10`
- **`StartLimitBurst` / `StartLimitIntervalSec` set** — see §7

**Not enabled at boot.** The unit is `wantedBy = []` and started on demand by `ib up`.

This deviates from the "starts at boot" phrasing in the option text approved during
design. Reason: booting would trigger an unattended IBKR authentication and a 2FA push to
Scott's phone on every startup, including boots that have nothing to do with trading.
The durable benefits of a system service — correct ownership, privilege separation,
independence from the desktop session — all hold regardless of boot enablement. Flip to
`wantedBy = [ "multi-user.target" ]` if unattended start is ever wanted.

### 6. Config assembly and secrets

Nix renders non-secret IBC settings to a store file — `TradingMode`, `IbDir`,
`OverrideTwsApiPort`, `ExistingSessionDetectedAction=primary`,
`SecondFactorAuthenticationTimeout=120`,
`ReloginAfterSecondFactorAuthenticationTimeout=yes`. These stay diffable in git.

`secrets/ibkr-creds.age` holds only:

```
IbLoginId=...
IbPassword=...
```

Registered in `secrets/secrets.nix` with recipients `eminix` and `scott`; declared with
`owner = "ibgateway"`, `mode = "0400"`.

`ExecStartPre` concatenates store template + decrypted creds into
`/run/ibgateway/ibc-config.ini` at `0400 ibgateway`. The password never enters the
world-readable Nix store, and settings changes do not require an agenix edit cycle.

### 7. Error handling

**Restart cap is the priority.** `StartLimitBurst=5` within `StartLimitIntervalSec=300`
turns the observed 4085-restart loop into a unit that fails visibly after five attempts.

`ExecStartPre` preflight, each failing fast with a distinct journal message:

- credentials file exists and is non-empty
- `/opt/ibgateway/jts/ibgateway/1046/jars` exists
- `/opt/ibgateway/jts` is writable by the service user — the exact condition that
  produced the silent 1109

IBC's `SecondFactorAuthenticationTimeout` and
`ReloginAfterSecondFactorAuthenticationTimeout` carry over so a missed 2FA push retries
rather than wedging.

### 8. `ib` CLI

`pkgs.writeShellApplication` defined in the module, into `environment.systemPackages`.
Same interface: `ib up [live|test]`, `ib down`, `ib status`.

Changes from `~/dotfiles/bin/ib`:

- `systemctl start ibgateway` (system unit) instead of `systemctl --user`
- Xvnc-starting logic removed — the module owns the display
- runtime deps pinned by `writeShellApplication`

A **polkit rule** grants `scott` manage rights on `ibgateway.service` only, keeping
`ib up live` password-free. Chosen over a sudo NOPASSWD rule as the narrower grant.

Minne services are still started by `ib` via `systemctl --user`, unchanged.

## Data flow — `ib up live`

1. polkit-authorized `systemctl start ibgateway.service`
2. unit pulls in `ibgateway-xvnc.service`
3. `ExecStartPre` validates preflight, assembles `/run/ibgateway/ibc-config.ini`
4. IBC launches the gateway under the JavaFX JDK on `:50`
5. IBC writes `jts.ini` to a now-writable `/opt/ibgateway/jts` — **no 1109**
6. JavaFX loads, login dialog renders, IBC submits credentials
7. **IBKR pushes 2FA to phone; Scott approves**
8. Gateway authenticates, opens port 4001
9. `ib` polls 4001 up to 120 s, then starts the Minne user units

## Verification

Build before switching — `nixos-rebuild build`, never a blind switch.

1. Unit reaches `active (running)`; no restart loop
2. `/opt/ibgateway/jts/jts.ini` exists after first start
3. IBC log passes `Creating minimal ... jts.ini` **without** exit 1109
4. `/var/lib/ibgateway/Jts/launcher.log` free of
   `ClassNotFoundException: javafx.scene.Parent`
5. `ib up live` → 2FA push arrives → port 4001 opens
6. `ib status` reports gateway active, 4001 open, Minne services active
7. **Reboot test** — display and service come up clean with no `/tmp` dependency. This is
   the property the previous setup never had.

## Cutover and cleanup

Remove only after the module is proven working:

- `~/bin/ibgateway-start.sh`, `~/bin/ibgateway-fhs`
- `~/.config/systemd/user/ibgateway.service`, `~/.config/systemd/user/xvfb.service`
- stray `Xvnc :50` process
- `/tmp/javafx-sdk/`
- `~/dotfiles/base/bin/ib` (duplicate)
- `/etc/ibgateway/ibc-config.ini` once agenix equivalent is confirmed

Keep `/opt/ibc` in place until the packaged IBC is confirmed working, then it may be
removed — the service will point at the store path.

Deployment follows the standard three-hop path (GitHub → datacore mirror → eminix pull),
then `nixos-rebuild`.

## Risks and notes

- **Password rotation recommended.** The IBKR password has been sitting in cleartext in a
  `0640 ibgateway:users` file, readable by any member of `users`, and was visible during
  diagnosis. Rotate when convenient; the agenix migration is a natural point.
- **IB Gateway auto-update** may rewrite `/opt/ibgateway`. Version `1046` is referenced in
  the preflight jars check; a forced upgrade to 10.47 will need that path updated. This is
  the accepted cost of keeping the payload imperative.
- **Laptop suspend** is explicitly out of scope. eminix is a T14; the gateway will still
  lose or wedge its session across suspend. If that proves annoying in practice, a
  systemd-sleep hook is the follow-up.
- Editing the agenix secret on eminix has a known Emacs/vterm gotcha (see
  `reference_agenix_secret_editing`) — use the Emacs-native path, not nano in vterm.
