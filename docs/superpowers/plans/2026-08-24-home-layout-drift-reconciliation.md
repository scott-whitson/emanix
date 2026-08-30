# Home-Layout Drift Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore datacore's backups, then bring rafik, datacore and whistle to a
four-directory home with an identical personal-project roster on the two personal hosts.

**Architecture:** Operations plan across three live hosts, not a code change. Every
task is additive or verified-then-destructive: an assertion is written and run
*before* the change (to observe the broken state), the change is applied, and the
same assertion is re-run as the gate. Personal projects travel by git through
GitHub; archives leave `$HOME` for `/srv/data`; the four-directory rule is already
declarative in `xdg.nix` and is applied rather than reinvented.

**Tech Stack:** zsh over SSH (tailnet), git, GitHub (`scott-whitson`), Syncthing
(REST API on `127.0.0.1:8384`), Backrest (connectrpc on `127.0.0.1:9898`),
restic → Backblaze B2, NixOS home-manager, systemd.

**Spec:** `docs/superpowers/specs/2026-08-24-home-layout-drift-reconciliation-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **Home top level, all hosts: exactly `docs`, `dotfiles`, `downloads`, `projects`.** Nothing else is created at `$HOME`.
- **Nothing is deleted, moved or overwritten until the data is verified safe elsewhere.** This is the plan's spine. Where a task deletes, its verification step must already have passed.
- **Phase 0A (Tasks 1-5) is a hard gate.** No task from Task 6 onward that moves or deletes data may run until Task 5 passes.
- **Push to GitHub only via the rafik relay.** whistle authenticates as `swhitsonCD`, which is read-only on `scott-whitson/emanix`. Never use whistle's identity for these repos. Recipe in Task 0.
- **After any relay push, `git fetch origin` before reading `git status`.** The push leaves whistle for the relay, never for `origin`, so `status -sb` reports a false `ahead N` until fetched.
- **All new GitHub repos are private.**
- **Do NOT remove the `websites` or `work-docs` Syncthing folders from datacore.** They are whistle's peer pairs and its only route to the work vault. Only `default` → `~/Sync` is vestigial.
- **Do NOT delete `rafik:~/emanix-installer.iso`.** It is a known-bad pubs-only image, retained as the baseline for the rebuild (spec R1).
- **`.stignore` first, `mv` second** in Task 22/23. Reversed, 4.4G of client data replicates to both personal hosts immediately.
- **Never reproduce the B2 account key or restic repo password** in any file, commit message, or log. Reference `RESTIC_PASSWORD_FILE=/etc/restic/password` and the existing config instead (spec R6).
- **Hosts:** `rafik` (NixOS/emanix, T14, personal), `datacore` (Debian 13, server, being replaced), `whistle` (NixOS WSL, work laptop). In datacore's Syncthing config rafik's device is still named `emanix`.

---

## Task 0: Reference — the rafik relay

Not a task to execute. The four commands every push in this plan uses.

```bash
ssh rafik 'rm -rf /tmp/emanix-relay.git && git clone --bare -q git@github.com:scott-whitson/<repo>.git /tmp/emanix-relay.git'
git push ssh://scott@rafik/tmp/emanix-relay.git main:main
ssh rafik 'cd /tmp/emanix-relay.git && git push origin main'
ssh rafik 'rm -rf /tmp/emanix-relay.git'
```

Use a temp **bare** clone, never rafik's own `~/projects/emanix` — that checkout is
on `main` and usually has an uncommitted file, so a push at its current branch
would be refused or would disturb a live daily driver.

---

## Task 1: Restore datacore's Backrest backup plan

**Files:**
- Modify: `datacore:~/.config/backrest/config.json` (live config; `backrest.service` runs as `User=scott`)
- Create: `datacore:~/projects/datacore-config/bootstrap/05a-backrest-plan.sh`
- Verify: `datacore:/var/log/restic-health-report.txt`

**Interfaces:**
- Consumes: nothing.
- Produces: a Backrest plan with `id: "datacore-daily"` on repo `scott-data-restic`, covering `/home/scott` and `/srv/data`. Task 5 asserts against it. Task 19 asserts `/srv/data/_archive/projects` appears inside a snapshot it produces.

- [ ] **Step 1: Write the failing assertion**

```bash
cat > /tmp/assert-backup-fresh.sh <<'EOF'
#!/bin/bash
# PASS if datacore's newest restic snapshot is under 26h old.
set -uo pipefail
rep=$(ssh datacore 'sudo -n cat /var/log/restic-health-report.txt 2>/dev/null')
age=$(echo "$rep" | sed -n 's/^Age: \([0-9]*\) hours$/\1/p')
[ -z "$age" ] && { echo "FAIL: no age line in report"; exit 1; }
echo "snapshot age: ${age}h"
[ "$age" -lt 26 ] && { echo "PASS"; exit 0; }
echo "FAIL: backup is ${age}h old"; exit 1
EOF
chmod +x /tmp/assert-backup-fresh.sh
```

- [ ] **Step 2: Run it to confirm the broken state**

Run: `ssh datacore 'sudo -n /usr/local/bin/restic-health-check.sh >/dev/null 2>&1'; /tmp/assert-backup-fresh.sh`
Expected: `FAIL: backup is 5xxh old` (about 527h as of 2026-08-24)

- [ ] **Step 3: Back up the live config, then read it**

```bash
ssh datacore 'cp -a ~/.config/backrest/config.json ~/.config/backrest/config.json.bak-predrift'
curl -s -X POST http://127.0.0.1:9898/v1.Backrest/GetConfig \
  -H 'Content-Type: application/json' -d '{}' > /tmp/backrest-config.json
python3 -c "import json;c=json.load(open('/tmp/backrest-config.json'));print('keys:',list(c));print('plans:',c.get('plans','ABSENT'))"
```

Run the `curl` **on datacore** (`ssh datacore '...'`); the port is bound `0.0.0.0:9898` but
keep it local. Expected: `plans: ABSENT`, confirming defect 1.

- [ ] **Step 4: Add the plan and write it back**

```bash
ssh datacore 'python3 - <<PY
import json, urllib.request
BASE="http://127.0.0.1:9898/v1.Backrest/"
def call(m, payload):
    r = urllib.request.Request(BASE+m, data=json.dumps(payload).encode(),
                              headers={"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(r))
cfg = call("GetConfig", {})
plan = {
  "id": "datacore-daily",
  "repo": "scott-data-restic",
  "paths": ["/home/scott", "/srv/data"],
  "excludes": ["/srv/data/media", "/srv/data/.snapshots", "/srv/data/lost+found"],
  "schedule": {"cron": "0 1 * * *", "clock": "CLOCK_LOCAL"},
}
cfg.setdefault("plans", [])
cfg["plans"] = [p for p in cfg["plans"] if p.get("id") != "datacore-daily"] + [plan]
out = call("SetConfig", cfg)
print("plans now:", [p["id"] for p in out.get("plans", [])])
PY'
```

If `SetConfig` returns a validation error, the message names the offending field —
correct that field and re-run this step. Do not hand-edit `config.json` while
`backrest.service` is running; it will be overwritten.

The dev-ephemera excludes (`node_modules`, `.venv`, `.git`, build dirs) already live
in `~/.config/restic/excludes.txt` and are applied by Backrest's restic invocation;
the `excludes` above add only the three path exclusions the retired
`05-restic-b2.sh` carried.

- [ ] **Step 5: Trigger a backup and wait for it**

```bash
ssh datacore 'python3 -c "
import json,urllib.request
r=urllib.request.Request(\"http://127.0.0.1:9898/v1.Backrest/Backup\",
  data=json.dumps({\"value\":\"datacore-daily\"}).encode(),
  headers={\"Content-Type\":\"application/json\"})
print(urllib.request.urlopen(r).status)"'
```

This is the first snapshot in 22 days and covers ~277G of changes; expect a long
run. Watch it: `ssh datacore 'journalctl -u backrest -f'`. Do not proceed until it
completes.

- [ ] **Step 6: Re-run the assertion**

Run: `ssh datacore 'sudo -n /usr/local/bin/restic-health-check.sh >/dev/null 2>&1'; /tmp/assert-backup-fresh.sh`
Expected: `snapshot age: 0h` then `PASS`

- [ ] **Step 7: Make it reproducible — commit the bootstrap script**

```bash
ssh datacore 'cat > ~/projects/datacore-config/bootstrap/05a-backrest-plan.sh <<EOF
#!/bin/bash
# 05a-backrest-plan.sh — ensure the datacore-daily Backrest plan exists.
# Idempotent. Backrest owns config.json at runtime, so go through its API,
# never by editing the file. Replaces the never-written 20-home-backup-scope.sh
# that RECOVERY.md referenced.
set -euo pipefail
python3 - <<PY
import json, urllib.request
BASE = "http://127.0.0.1:9898/v1.Backrest/"
def call(m, payload):
    r = urllib.request.Request(BASE + m, data=json.dumps(payload).encode(),
                               headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(r))
cfg = call("GetConfig", {})
plan = {
  "id": "datacore-daily",
  "repo": "scott-data-restic",
  "paths": ["/home/scott", "/srv/data"],
  "excludes": ["/srv/data/media", "/srv/data/.snapshots", "/srv/data/lost+found"],
  "schedule": {"cron": "0 1 * * *", "clock": "CLOCK_LOCAL"},
}
cfg.setdefault("plans", [])
if any(p.get("id") == "datacore-daily" for p in cfg["plans"]):
    print("[ok] datacore-daily plan already present"); raise SystemExit
cfg["plans"].append(plan)
call("SetConfig", cfg)
print("[done] datacore-daily plan created")
PY
EOF
chmod +x ~/projects/datacore-config/bootstrap/05a-backrest-plan.sh
cd ~/projects/datacore-config && git add bootstrap/05a-backrest-plan.sh && git commit -q -m "bootstrap: 05a — ensure the datacore-daily Backrest plan exists

Backrest had a B2 repo and a retention policy but no plans key at all, so the
daemon ran with nothing scheduled and snapshots stopped 2026-08-02 when the old
restic-backup service was retired. This is the missing implementation behind
RECOVERY.md step 20, which never existed in any commit." && git push origin master 2>&1 | tail -2'
```

datacore authenticates to GitHub as `scott-whitson` directly; no relay needed here.

---

## Task 2: Fix the malformed heartbeat status

**Files:**
- Modify: `datacore:/usr/local/bin/restic-health-check.sh`
- Verify: `comsat:/var/lib/comsat/backups/datacore.json`

**Interfaces:**
- Consumes: Task 1's working plan (so the status line reads OK, proving both branches).
- Produces: a single-line `/var/run/restic-health-status` and therefore valid JSON in the heartbeat. Task 3 relies on `status` being parseable.

- [ ] **Step 1: Write the failing assertion**

```bash
cat > /tmp/assert-heartbeat-json.sh <<'EOF'
#!/bin/bash
# PASS if datacore's heartbeat on comsat is valid JSON.
set -uo pipefail
j=$(ssh rafik 'ssh comsat "cat /var/lib/comsat/backups/datacore.json"' 2>/dev/null)
echo "$j" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("status:", repr(d["status"])); print("PASS")' \
  || { echo "FAIL: heartbeat is not valid JSON"; exit 1; }
EOF
chmod +x /tmp/assert-heartbeat-json.sh
```

`comsat` resolves only from rafik's hand-written root `~/.ssh/config`, so it must be
reached through rafik — it does not resolve from whistle.

- [ ] **Step 2: Run it to confirm the broken state**

Run: `/tmp/assert-heartbeat-json.sh`
Expected: `FAIL: heartbeat is not valid JSON` — the `status` value contains a literal newline.

- [ ] **Step 3: Make the status file single-line**

The script writes `echo "OK:backrest" > "$STATUS_FILE"` and then `echo
"...:snapshot:...h" >> "$STATUS_FILE"`, producing two lines. Join them with a
semicolon instead:

```bash
ssh datacore 'sudo -n cp -a /usr/local/bin/restic-health-check.sh /usr/local/bin/restic-health-check.sh.bak-predrift
sudo -n python3 - <<PY
import pathlib
p = pathlib.Path("/usr/local/bin/restic-health-check.sh")
s = p.read_text()
# every status write after the first becomes an in-place append to one line
s = s.replace(">> \"\$STATUS_FILE\"", "| tr -d \"\\\\n\" >> \"\$STATUS_FILE\"")
# the FAIL:backrest branch also used >>; normalise the separator
s = s.replace("echo \"OK:backrest\" > \"\$STATUS_FILE\"",
              "printf \"OK:backrest\" > \"\$STATUS_FILE\"")
s = s.replace("echo \"FAIL:backrest\" > \"\$STATUS_FILE\"",
              "printf \"FAIL:backrest\" > \"\$STATUS_FILE\"")
p.write_text(s)
print("patched")
PY'
```

Then read the three status-writing lines back and confirm each appends without a
newline: `ssh datacore 'grep -n STATUS_FILE /usr/local/bin/restic-health-check.sh'`.
Adjust by hand if the substitution missed a branch — correctness here matters more
than the one-liner.

- [ ] **Step 4: Run the check and re-assert**

Run: `ssh datacore 'sudo -n /usr/local/bin/restic-health-check.sh >/dev/null 2>&1'; sleep 5; /tmp/assert-heartbeat-json.sh`
Expected: `status: 'OK:backrest;OK:snapshot:0h'` then `PASS`

- [ ] **Step 5: Do NOT commit the script yet**

The script hardcodes the B2 account id and key in three separate command
invocations. Copying it into `datacore-config` as-is would push live credentials
to GitHub — the same failure mode as the ionapi leak, which cost a full history
rewrite. Tracking it is correct, but only after Task 3 strips the secrets. Leave
the patched script in `/usr/local/bin` for now and move on.

---

## Task 3: Strip B2 credentials out of the health-check script, then track it

**Files:**
- Create: `datacore:/etc/restic/b2.env` (mode `0600`, root)
- Modify: `datacore:/usr/local/bin/restic-health-check.sh`
- Create: `datacore:~/projects/datacore-config/bin/restic-health-check.sh` (sanitised copy, tracked)

**Interfaces:**
- Consumes: Task 2's single-line status fix.
- Produces: `/etc/restic/b2.env` exporting `B2_ACCOUNT_ID` and `B2_ACCOUNT_KEY`. Any future script needing B2 sources this file rather than inlining values.

- [ ] **Step 1: Write the failing assertion**

```bash
cat > /tmp/assert-no-inline-b2.sh <<'EOF'
#!/bin/bash
# PASS if no B2 credential literal appears in the tracked repo or the live script.
set -uo pipefail
hits=$(ssh datacore 'sudo -n grep -lE "B2_ACCOUNT_(ID|KEY)=[A-Za-z0-9]" /usr/local/bin/restic-health-check.sh 2>/dev/null; grep -rlE "B2_ACCOUNT_(ID|KEY)=[A-Za-z0-9]" ~/projects/datacore-config 2>/dev/null')
[ -z "$hits" ] && { echo "PASS: no inline B2 credentials"; exit 0; }
echo "FAIL: inline credentials in:"; echo "$hits"; exit 1
EOF
chmod +x /tmp/assert-no-inline-b2.sh
```

- [ ] **Step 2: Run it to confirm the broken state**

Run: `/tmp/assert-no-inline-b2.sh`
Expected: `FAIL: inline credentials in:` followed by `/usr/local/bin/restic-health-check.sh`

- [ ] **Step 3: Move the credentials into a root-only env file**

Read the two values from the running script, write them to `/etc/restic/b2.env`,
and confirm the file is root-only. Do not echo the values to the terminal.

```bash
ssh datacore 'sudo -n bash -c "
  set -euo pipefail
  id=\$(grep -oPm1 \"(?<=B2_ACCOUNT_ID=)[A-Za-z0-9]+\" /usr/local/bin/restic-health-check.sh)
  key=\$(grep -oPm1 \"(?<=B2_ACCOUNT_KEY=)[A-Za-z0-9]+\" /usr/local/bin/restic-health-check.sh)
  install -d -m 700 /etc/restic
  printf \"export B2_ACCOUNT_ID=%s\nexport B2_ACCOUNT_KEY=%s\n\" \"\$id\" \"\$key\" > /etc/restic/b2.env
  chmod 600 /etc/restic/b2.env
  echo wrote /etc/restic/b2.env
"; sudo -n ls -la /etc/restic/b2.env'
```

Expected: `-rw------- 1 root root ... /etc/restic/b2.env`

- [ ] **Step 4: Replace the three inline pairs with a source**

```bash
ssh datacore 'sudo -n python3 - <<PY
import pathlib, re
p = pathlib.Path("/usr/local/bin/restic-health-check.sh")
s = p.read_text()
s = re.sub(r"\n\s*B2_ACCOUNT_ID=[A-Za-z0-9]+ *\\\\\n\s*B2_ACCOUNT_KEY=[A-Za-z0-9]+ *\\\\", " \\\\", s)
if "source /etc/restic/b2.env" not in s:
    s = s.replace("set -euo pipefail",
                  "set -euo pipefail\n\n# B2 credentials live outside this script so it can be version-controlled.\nsource /etc/restic/b2.env")
p.write_text(s)
print("patched")
PY
sudo -n grep -n "B2_ACCOUNT\|source /etc/restic" /usr/local/bin/restic-health-check.sh'
```

The three restic invocations already run under `sudo`, which by default strips the
environment — verify each one still passes the credentials through. If any lost
them, add `B2_ACCOUNT_ID="$B2_ACCOUNT_ID" B2_ACCOUNT_KEY="$B2_ACCOUNT_KEY"` to that
`sudo` line explicitly. Expected: `source /etc/restic/b2.env` present, no
`B2_ACCOUNT_KEY=<literal>` remaining.

- [ ] **Step 5: Prove the script still works**

Run: `ssh datacore 'sudo -n /usr/local/bin/restic-health-check.sh'`
Expected: report prints, `Total snapshots:` is a number greater than 19, and no
`FAIL: Could not retrieve snapshots`. If snapshots cannot be retrieved, the `sudo`
environment stripping bit you — return to Step 4.

- [ ] **Step 6: Now track the sanitised script and re-assert**

```bash
ssh datacore 'mkdir -p ~/projects/datacore-config/bin
sudo -n cp /usr/local/bin/restic-health-check.sh ~/projects/datacore-config/bin/restic-health-check.sh
sudo -n chown scott:scott ~/projects/datacore-config/bin/restic-health-check.sh
grep -c "B2_ACCOUNT_KEY=" ~/projects/datacore-config/bin/restic-health-check.sh'
/tmp/assert-no-inline-b2.sh
```

Expected: `grep -c` prints `0`, then `PASS: no inline B2 credentials`. **If the grep
prints anything other than 0, stop — do not commit.**

- [ ] **Step 7: Commit**

```bash
ssh datacore 'cd ~/projects/datacore-config && git add bin/restic-health-check.sh && git commit -q -m "bin: track restic-health-check.sh, credentials sourced from /etc/restic/b2.env

The script hardcoded the B2 account id and key in three restic invocations,
which blocked version-controlling it at all. They now live in a root-only
/etc/restic/b2.env. Also carries the single-line status fix: the status file was
written with > then >>, so the heartbeat JSON contained a literal newline inside
the status value and every downstream parser choked.

Untracked root scripts do not survive a host rebuild; this one now will." && git push origin master 2>&1 | tail -2'
```

Note the repo password also sits plaintext in `~/.config/backrest/config.json`.
That file is Backrest-owned and `0600`; leave it, and prefer agenix for both when
datacore becomes a NixOS host (spec R6).

---

## Task 4: Make Comsat alert on backup status, not just heartbeat freshness

**Files:**
- Modify: `comsat:/usr/local/bin/comsat-health-backup.sh`
- Verify: `comsat:/var/lib/comsat/datacore.backup-status`

**Interfaces:**
- Consumes: Task 3's valid, single-line `status` field.
- Produces: an alert path that fires on `FAIL:` or `WARN:` in the payload. This is what makes every later gate in this plan trustworthy.

**Why this task exists:** this is the defect that hid the outage for 22 days. Comsat
checked only that a heartbeat had arrived recently. A heartbeat arriving daily and
saying `FAIL:snapshot:527h` therefore read as `ok`. Fixing the backup without
fixing this leaves the next silent failure equally silent.

- [ ] **Step 1: Read the current checker**

Run: `ssh rafik 'ssh comsat "cat /usr/local/bin/comsat-health-backup.sh"'`
Read it fully before editing. Identify where it writes
`/var/lib/comsat/datacore.backup-status` and where it decides to alert.

- [ ] **Step 2: Write the failing assertion**

```bash
cat > /tmp/assert-status-aware.sh <<'EOF'
#!/bin/bash
# PASS if a fresh heartbeat carrying FAIL produces a non-ok comsat status.
set -uo pipefail
ssh rafik 'ssh comsat "sudo cp /var/lib/comsat/backups/datacore.json /tmp/dc.json.real
sudo python3 -c \"
import json,datetime
d=json.load(open(\\\"/tmp/dc.json.real\\\"))
d[\\\"status\\\"]=\\\"OK:backrest;FAIL:snapshot:999h\\\"
d[\\\"timestamp\\\"]=datetime.datetime.utcnow().strftime(\\\"%Y-%m-%dT%H:%M:%SZ\\\")
json.dump(d,open(\\\"/var/lib/comsat/backups/datacore.json\\\",\\\"w\\\"))
\"
sudo /usr/local/bin/comsat-health-backup.sh >/dev/null 2>&1
cat /var/lib/comsat/datacore.backup-status
sudo cp /tmp/dc.json.real /var/lib/comsat/backups/datacore.json"' > /tmp/synthetic-status.txt
st=$(cat /tmp/synthetic-status.txt | tr -d '[:space:]')
echo "status under synthetic FAIL: '$st'"
[ "$st" != "ok" ] && { echo "PASS"; exit 0; }
echo "FAIL: comsat reported ok despite a FAIL payload"; exit 1
EOF
chmod +x /tmp/assert-status-aware.sh
```

This injects a synthetic FAIL heartbeat, runs the checker, reads the verdict, then
restores the real heartbeat. It is safe to run repeatedly.

- [ ] **Step 3: Run it to confirm the broken state**

Run: `/tmp/assert-status-aware.sh`
Expected: `status under synthetic FAIL: 'ok'` then `FAIL: comsat reported ok despite a FAIL payload`

- [ ] **Step 4: Fix the missing EnvironmentFile — no alert can currently send**

**Read 2026-08-24, after this plan was first written.** `comsat-health.service`
carries `EnvironmentFile=/etc/comsat/comsat.env`; **`comsat-health-backup.service`
does not.** Its `TELEGRAM_BOT_TOKEN` is therefore empty, and `send_telegram()`
takes its `[[ -z "$TELEGRAM_BOT_TOKEN" ]]` branch — logging "not set, skipping" and
returning. No alert this monitor raises can ever be delivered. `BACKUP_FAIL` count
in the log is `0`, so this path has never once run.

```bash
ssh rafik 'ssh comsat "sudo systemctl edit --full --force comsat-health-backup.service"'
```

Add `EnvironmentFile=/etc/comsat/comsat.env` to its `[Service]` section, matching
`comsat-health.service`, then `sudo systemctl daemon-reload && sudo systemctl
restart comsat-health-backup.service`. Do not print the token.

- [ ] **Step 4b: Make check_backup act on the status it already parses**

The defect is exact. `check_backup()` parses and *logs* the status, then ignores it:

```bash
status=$(sed -n "s/.*\"status\": \"\([^\"]*\)\".*/\1/p" "$BACKUP_JSON" | head -1)
log "BACKUP_CHECK: age=${age_hours}h status=${status}"
if (( age_hours > MAX_BACKUP_AGE_HOURS )); then
    echo "stale" > "$BACKUP_STATUS"; log "BACKUP_FAIL: ..."; return 1
fi
echo "ok" > "$BACKUP_STATUS"   # <-- status never consulted
return 0
```

Back it up, then insert a status check between the age check and the final `ok`:

```bash
ssh rafik 'ssh comsat "sudo cp -a /usr/local/bin/comsat-health-backup.sh /usr/local/bin/comsat-health-backup.sh.bak-predrift"'
```

The inserted logic must: treat a `status` containing `FAIL` as failure (write
`fail`, log `BACKUP_FAIL`, `return 1`); treat `WARN` as failure too, since a
warning nobody sees is the same as no warning; and treat an **empty or unparseable
`status` as failure**, because that is precisely how defect 3 hid inside defect 2 —
the sed class `[^"]*` cannot cross the newline in the malformed payload, so it
matched nothing and the log printed `status=` blank for weeks. Keep the existing
age and missing-file conditions exactly as they are: correct, merely insufficient.

After Task 2, a healthy payload reads `OK:backrest;OK:snapshot:3h`.

- [ ] **Step 5: Re-run the assertion**

Run: `/tmp/assert-status-aware.sh`
Expected: `status under synthetic FAIL:` shows something other than `ok`, then `PASS`

- [ ] **Step 6: Confirm the real heartbeat still reads healthy**

Run: `ssh rafik 'ssh comsat "sudo /usr/local/bin/comsat-health-backup.sh >/dev/null 2>&1; cat /var/lib/comsat/datacore.backup-status"'`
Expected: `ok` — the synthetic payload was restored, and after Task 1 the genuine
status is `OK:backrest;OK:snapshot:Nh`.

- [ ] **Step 7: Confirm an alert actually reaches you**

An alert path that nobody receives is defect 2 again in a new costume. Trigger one
real Telegram alert and confirm it arrives on your phone:

```bash
/tmp/assert-status-aware.sh   # injects FAIL, which should now alert
```

If no Telegram message arrives, the alert transport is a fourth defect — chase it
before treating this task as done.

---

## Task 5: GATE — Phase 0A verification

**Files:**
- Create: `datacore:~/projects/datacore-config/bin/backup-gate.sh`

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: a single command that must exit 0 before any data-moving task runs.

**No task from Task 6 onward that moves or deletes data may run until this exits 0.**

- [ ] **Step 1: Write the gate**

```bash
cat > /tmp/backup-gate.sh <<'EOF'
#!/bin/bash
# Phase 0A gate. Exit 0 only if datacore's backups are demonstrably working.
set -uo pipefail
fail=0
echo "== 1. snapshot freshness =="
/tmp/assert-backup-fresh.sh || fail=1
echo "== 2. heartbeat is valid JSON =="
/tmp/assert-heartbeat-json.sh || fail=1
echo "== 3. no inline B2 credentials =="
/tmp/assert-no-inline-b2.sh || fail=1
echo "== 4. comsat is status-aware =="
/tmp/assert-status-aware.sh || fail=1
echo "== 5. plan is scheduled, not just present =="
ssh datacore 'python3 -c "
import json,urllib.request
r=urllib.request.Request(\"http://127.0.0.1:9898/v1.Backrest/GetConfig\",data=b\"{}\",headers={\"Content-Type\":\"application/json\"})
c=json.load(urllib.request.urlopen(r))
p=[x for x in c.get(\"plans\",[]) if x[\"id\"]==\"datacore-daily\"]
assert p, \"datacore-daily plan missing\"
print(\"paths:\", p[0][\"paths\"]); print(\"schedule:\", p[0].get(\"schedule\"))
"' || fail=1
[ "$fail" -eq 0 ] && { echo; echo "GATE PASS"; exit 0; }
echo; echo "GATE FAIL"; exit 1
EOF
chmod +x /tmp/backup-gate.sh
```

- [ ] **Step 2: Run the gate**

Run: `/tmp/backup-gate.sh`
Expected: all five checks pass, then `GATE PASS`

- [ ] **Step 3: Commit the gate so it is re-runnable after the cutover**

```bash
scp /tmp/backup-gate.sh datacore:~/projects/datacore-config/bin/backup-gate.sh
ssh datacore 'cd ~/projects/datacore-config && chmod +x bin/backup-gate.sh && git add bin/backup-gate.sh && git commit -q -m "bin: backup-gate.sh — five checks that datacore backups actually work

Snapshot freshness, heartbeat JSON validity, absence of inline B2 credentials,
comsat status-awareness, and a scheduled (not merely present) Backrest plan.
Re-run this after the NixOS cutover before trusting backups again." && git push origin master 2>&1 | tail -2'
```

- [ ] **Step 4: Record the outcome before proceeding**

Note in the session which of the five checks passed and the age of the new
snapshot. Phase 0A is the only gate in this plan whose failure means *stop
entirely* rather than *fix and retry*.

---

## Task 6: Preflight — create the five private repos

**Files:** none locally. GitHub only.

**Interfaces:**
- Produces: empty private repos `scott-whitson/{fragpaper,mardy,chstr,swc,typ}`. Tasks 9-13 push into them.

**Requires Scott.** `gh` is authenticated on no host — absent on datacore, not
logged in on whistle — so this is the web UI or a personal access token.
`websites` is deliberately **not** in this list (spec: `websites.git` is already an
origin).

- [ ] **Step 1: Scott creates five empty private repos**

`fragpaper`, `mardy`, `chstr`, `swc`, `typ`. No README, no `.gitignore`, no
license — an initial commit on GitHub's side would force a merge on first push.

- [ ] **Step 2: Verify each exists, is empty, and is private**

```bash
for r in fragpaper mardy chstr swc typ; do
  printf "%-11s " "$r"
  ssh rafik "git ls-remote git@github.com:scott-whitson/$r.git 2>&1 | head -1" \
    | sed 's/^$/EMPTY (good)/'
done
```
Expected: every line reads `EMPTY (good)`. A line showing a ref means the repo has
commits — reconcile before pushing. An error means it does not exist or is not
visible to rafik's key.

- [ ] **Step 3: Confirm private**

Ask Scott to confirm all five show the `Private` badge, or check with a token. A
public `swc` would expose the live scottwhitson.com application.

---

## Task 7: Secret scan and .gitignore for chstr, swc and typ

**Files:**
- Create: `datacore:~/projects/{chstr,swc,typ}/.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: three `.gitignore` files. Tasks 11-13 commit them as part of each repo's initial commit.

These are first-ever commits of trees that have never been version controlled. The
ionapi leak required a full history rewrite across every ref; a filename sweep is
not sufficient evidence of cleanliness.

- [ ] **Step 1: Content-scan all three trees**

```bash
ssh datacore 'nix-shell -p gitleaks --run "for n in chstr swc typ; do echo \"=== \$n ===\"; gitleaks detect --no-git --source ~/projects/\$n --redacted -v 2>&1 | tail -25; done"' 2>&1 | tail -80
```

datacore is Debian without nix-shell in every context; if that fails, run the scan
from rafik against a temporary copy, or install gitleaks locally. Do not skip this
step and do not substitute a filename glob for it.

- [ ] **Step 2: Report findings and stop if anything is found**

If gitleaks reports any finding, **stop and report to Scott before writing a single
commit.** Per spec R2 the response is rotate-the-credential, not
scrub-and-move-on. Redacted output only — never paste a secret value into the
session, a commit message, or this plan.

- [ ] **Step 3: Write the three .gitignore files**

Each tree carries a 51M `.claude/mind.mv2` agent database — 153M of the 243M total
and not source.

```bash
ssh datacore 'for n in chstr swc typ; do cat > ~/projects/$n/.gitignore <<EOF
# Agent database — 51M, machine-local, never source
/.claude/

# Python / node ephemera
__pycache__/
*.pyc
.venv/
venv/
node_modules/
.pytest_cache/
.mypy_cache/
.ruff_cache/

# Build output
dist/
build/
target/
EOF
done; echo written'
```

- [ ] **Step 4: Decide the two large-asset questions with Scott**

Neither has a safe default; both change what the first commit contains.

- **`chstr/chs/engine/stockfish_13_x64_mac` (21M)** — a vendored macOS Stockfish
  binary on a Linux-only fleet. Recommend ignoring it: it is a redistributable
  upstream artifact, wrong-platform, and dominates the repo. Confirm with Scott.
- **`swc/static/images` (34M) and `swc/manim` (33M)** — `swc` is the live FastAPI
  app serving scottwhitson.com from `/srv/swc`. `static/images` is almost certainly
  served content and must be **kept**. `manim` is animation sources; ask whether
  rendered output inside it can be ignored.

Append the agreed ignores to the relevant `.gitignore` before Tasks 12 and 13.

- [ ] **Step 5: Confirm the resulting sizes**

```bash
ssh datacore 'for n in chstr swc typ; do printf "%-6s " $n; git -C ~/projects/$n 2>/dev/null status >/dev/null; du -sh --exclude=.claude ~/projects/$n | cut -f1; done'
```
Expected roughly: `typ` 200K, `chstr` 24M (3M if stockfish is ignored), `swc` 67M.

---

## Task 8: Reconcile minne

**Files:**
- Modify: `rafik:~/projects/minne` (working tree, 20 dirty files)
- Verify: `datacore:~/projects/minne`

**Interfaces:**
- Consumes: nothing.
- Produces: `origin/master` on `scott-whitson/minne` containing both hosts' work; both clones clean and level.

**Requires Scott's judgment.** 1.1G repo, 5 unpushed commits on each host and 20
dirty files on rafik. Do not discard anything on your own initiative.

- [ ] **Step 1: Establish whether the two hosts' unpushed commits are the same**

```bash
echo "=== rafik ==="; ssh rafik 'git -C ~/projects/minne log --oneline -6 master; echo "--- unpushed ---"; git -C ~/projects/minne log --oneline @{u}..HEAD 2>/dev/null'
echo "=== datacore ==="; ssh datacore 'git -C ~/projects/minne log --oneline -6 master; echo "--- unpushed ---"; git -C ~/projects/minne log --oneline @{u}..HEAD 2>/dev/null'
```

Compare the commit *hashes*, not the messages. Identical hashes mean one push
resolves both. Divergent hashes mean a genuine fork and Scott chooses.

- [ ] **Step 2: Show Scott the 20 dirty files on rafik**

```bash
ssh rafik 'git -C ~/projects/minne status --porcelain; echo "--- diffstat ---"; git -C ~/projects/minne diff --stat'
```

Report the list and the diffstat. Ask whether to commit, stash, or discard. **Do
not run `checkout --` or `clean` without an explicit instruction naming the files.**

- [ ] **Step 3: Act on Scott's decision, then fetch both hosts**

```bash
ssh rafik 'git -C ~/projects/minne fetch -q origin && git -C ~/projects/minne status -sb | head -2'
ssh datacore 'git -C ~/projects/minne fetch -q origin && git -C ~/projects/minne status -sb | head -2'
```

Note the stale-ref rule: read `status -sb` only after `fetch`.

- [ ] **Step 4: Push from the host that holds the authoritative history**

rafik and datacore both authenticate as `scott-whitson`, so push directly from
whichever host Scott designates — no relay needed for `minne`.

Run: `ssh <host> 'git -C ~/projects/minne push origin master'`

- [ ] **Step 5: Verify both clones are clean and level**

```bash
for h in rafik datacore; do printf "%-9s " $h; ssh $h 'git -C ~/projects/minne fetch -q origin; git -C ~/projects/minne status -sb | head -1'; done
```
Expected: both `## master...origin/master` with no ahead/behind marker.

---

## Task 9: Give fragpaper a remote and push

**Files:**
- Modify: `datacore:~/projects/fragpaper/.git/HEAD` (via `git symbolic-ref`)

**Interfaces:**
- Consumes: Task 6's empty `fragpaper` repo.
- Produces: `scott-whitson/fragpaper` with 38 commits on `main`. Task 15 clones it to rafik.

Its 38 commits are on `main`; HEAD is checked out on an empty `master`, which is why
an earlier survey reported "no commits yet".

- [ ] **Step 1: Confirm the branch layout**

```bash
ssh datacore 'cd ~/projects/fragpaper && git symbolic-ref HEAD; git for-each-ref --format="%(refname:short) %(objectname:short)" refs/heads; git log --oneline -3 main'
```
Expected: HEAD on `master`, `main` present with commits, `master` absent from
`refs/heads` or empty.

- [ ] **Step 2: Repoint HEAD onto main**

```bash
ssh datacore 'cd ~/projects/fragpaper && git symbolic-ref HEAD refs/heads/main && git branch -D master 2>/dev/null; git status -sb | head -3'
```
Expected: `## main`, and the working tree reports no deletions. If `git status`
shows the whole tree as deleted, HEAD and the index disagree — run
`git reset --mixed main` and re-check before continuing.

- [ ] **Step 3: Add the remote and push**

```bash
ssh datacore 'cd ~/projects/fragpaper && git remote add origin git@github.com:scott-whitson/fragpaper.git && git push -u origin main 2>&1 | tail -3'
```

- [ ] **Step 4: Verify**

Run: `ssh datacore 'cd ~/projects/fragpaper && git fetch -q origin && git status -sb | head -1 && git log --oneline -1 origin/main'`
Expected: `## main...origin/main` with no divergence marker.

---

## Task 10: Give mardy a remote and push

**Files:** none created; `datacore:~/projects/mardy` gains a remote.

**Interfaces:**
- Consumes: Task 6's empty `mardy` repo.
- Produces: `scott-whitson/mardy` with 9 commits on `master`. Task 15 clones it to rafik.

- [ ] **Step 1: Confirm the state**

```bash
ssh datacore 'cd ~/projects/mardy && git status -sb | head -2; git log --oneline -3; git remote -v'
```
Expected: `master`, 9 commits, no remote, clean tree.

- [ ] **Step 2: Add the remote and push**

```bash
ssh datacore 'cd ~/projects/mardy && git remote add origin git@github.com:scott-whitson/mardy.git && git push -u origin master 2>&1 | tail -3'
```

- [ ] **Step 3: Verify**

Run: `ssh datacore 'cd ~/projects/mardy && git fetch -q origin && git status -sb | head -1'`
Expected: `## master...origin/master` with no divergence marker.

---

## Task 11: Initialise and push typ

**Files:**
- Create: `datacore:~/projects/typ/.git` (fresh)

**Interfaces:**
- Consumes: Task 6's empty `typ` repo; Task 7's `.gitignore` and clean scan.
- Produces: `scott-whitson/typ` with one initial commit on `main`. Task 15 clones it to rafik.

`typ` is the smallest of the three history-less trees (~200K of Rust source after
ignores) — do it first to prove the sequence before applying it to the larger two.

- [ ] **Step 1: Remove the empty .git skeleton**

```bash
ssh datacore 'cd ~/projects/typ && ls -A .git; rm -rf .git && echo "skeleton removed"'
```
Expected: the listing shows `branches hooks info logs objects refs` with no `HEAD`
or `config` — the unusable skeleton described in the spec. Nothing of value is
lost: it holds zero objects and zero refs.

- [ ] **Step 2: Init, stage, and inspect what would be committed**

```bash
ssh datacore 'cd ~/projects/typ && git init -q -b main && git add -A && git status --short | head -30; echo "--- file count ---"; git diff --cached --name-only | wc -l; echo "--- largest staged ---"; git diff --cached --name-only -z | xargs -0 du -h 2>/dev/null | sort -rh | head -5'
```

Read this output before committing. `.claude/` must not appear. Nothing over a few
MB should appear unless Task 7 agreed to keep it.

- [ ] **Step 3: Commit and push**

```bash
ssh datacore 'cd ~/projects/typ && git commit -q -m "Initial commit: import existing working tree

This tree had no git history — its .git held zero objects and zero refs, so
nothing could be recovered. The working tree is therefore taken as truth and
imported as a single initial commit." && git remote add origin git@github.com:scott-whitson/typ.git && git push -u origin main 2>&1 | tail -3'
```

- [ ] **Step 4: Verify**

Run: `ssh datacore 'cd ~/projects/typ && git fetch -q origin && git status -sb | head -1; git ls-files | wc -l'`
Expected: `## main...origin/main` with no divergence, and a plausible file count.

---

## Task 12: Initialise and push chstr

**Files:**
- Create: `datacore:~/projects/chstr/.git` (fresh)

**Interfaces:**
- Consumes: Task 6's empty `chstr` repo; Task 7's `.gitignore`, clean scan, and the stockfish decision.
- Produces: `scott-whitson/chstr` with one initial commit on `main`. Task 15 clones it to rafik.

`chstr/.git` is completely empty — not even the skeleton the other two have.

- [ ] **Step 1: Remove the empty .git and confirm the stockfish decision is applied**

```bash
ssh datacore 'cd ~/projects/chstr && ls -A .git; rm -rf .git; grep -n stockfish .gitignore || echo "stockfish NOT ignored — confirm this is intended"'
```

- [ ] **Step 2: Init, stage, and inspect**

```bash
ssh datacore 'cd ~/projects/chstr && git init -q -b main && git add -A && echo "--- file count ---"; git diff --cached --name-only | wc -l; echo "--- largest staged ---"; git diff --cached --name-only -z | xargs -0 du -h 2>/dev/null | sort -rh | head -5'
```
`.claude/mind.mv2` must be absent. If stockfish was agreed as ignored, it must be
absent too.

- [ ] **Step 3: Commit and push**

```bash
ssh datacore 'cd ~/projects/chstr && git commit -q -m "Initial commit: import existing working tree

This tree had no git history — .git was entirely empty, so nothing could be
recovered. The working tree is taken as truth and imported as a single initial
commit." && git remote add origin git@github.com:scott-whitson/chstr.git && git push -u origin main 2>&1 | tail -3'
```

- [ ] **Step 4: Verify**

Run: `ssh datacore 'cd ~/projects/chstr && git fetch -q origin && git status -sb | head -1'`
Expected: `## main...origin/main` with no divergence marker.

---

## Task 13: Initialise and push swc

**Files:**
- Create: `datacore:~/projects/swc/.git` (fresh)

**Interfaces:**
- Consumes: Task 6's empty **private** `swc` repo; Task 7's `.gitignore`, clean scan, and the static/manim decision.
- Produces: `scott-whitson/swc` with one initial commit on `main`. Task 15 clones it to rafik.

**`swc` is live production** — the FastAPI + Jinja2 + Tailwind app serving
scottwhitson.com from `/srv/swc`. Treat the first commit with production care, and
confirm the repo is private before pushing. Note `swc` also carries a
`.env.example`; check that no real `.env` is staged.

- [ ] **Step 1: Confirm privacy and check for a real .env**

```bash
ssh datacore 'cd ~/projects/swc && ls -la .env .env.* 2>/dev/null; grep -n "^/.env" .gitignore || echo ".env NOT ignored — add it before staging"'
```
If a real `.env` exists, add `/.env` to `.gitignore` before Step 3. Re-confirm with
Scott that the GitHub repo shows `Private`.

- [ ] **Step 2: Remove the empty .git skeleton**

```bash
ssh datacore 'cd ~/projects/swc && ls -A .git; rm -rf .git && echo "skeleton removed"'
```

- [ ] **Step 3: Init, stage, and inspect carefully**

```bash
ssh datacore 'cd ~/projects/swc && git init -q -b main && git add -A && echo "--- file count ---"; git diff --cached --name-only | wc -l; echo "--- largest staged ---"; git diff --cached --name-only -z | xargs -0 du -h 2>/dev/null | sort -rh | head -8; echo "--- any env/secret staged? ---"; git diff --cached --name-only | grep -iE "\.env$|secret|credential|\.pem$|\.key$" || echo none'
```
Expected: `none` on the last check, `.claude/mind.mv2` absent, `static/images`
present if Task 7 agreed to keep it.

- [ ] **Step 4: Commit and push**

```bash
ssh datacore 'cd ~/projects/swc && git commit -q -m "Initial commit: import existing working tree

This tree had no git history — its .git held zero objects and zero refs. The
working tree is taken as truth and imported as a single initial commit.

swc serves scottwhitson.com from /srv/swc; static/images is served content and is
tracked deliberately." && git remote add origin git@github.com:scott-whitson/swc.git && git push -u origin main 2>&1 | tail -3'
```

- [ ] **Step 5: Verify, and confirm the running app is untouched**

```bash
ssh datacore 'cd ~/projects/swc && git fetch -q origin && git status -sb | head -1'
curl -s -o /dev/null -w "scottwhitson.com: %{http_code}\n" https://scottwhitson.com
```
Expected: `## main...origin/main` with no divergence, and the site still returns
`200`. Nothing in this task touches `/srv/swc`, but verify rather than assume.

---

## Task 14: GATE — every personal project is durable

**Files:**
- Create: `/tmp/assert-durable.sh`

**Interfaces:**
- Consumes: Tasks 8-13.
- Produces: proof that no personal project exists only on one machine. Task 15 onward may then clone and, later, delete.

- [ ] **Step 1: Write the gate**

```bash
cat > /tmp/assert-durable.sh <<'EOF'
#!/bin/bash
# Every personal project on either host must have a remote and nothing unpushed.
# websites.git is exempt: it IS an origin, by design.
set -uo pipefail
fail=0
for h in rafik datacore; do
  echo "=== $h ==="
  ssh $h 'for d in ~/projects/*/; do
    n=$(basename "$d")
    case "$n" in work|websites.git|_archive|archive) continue;; esac
    if [ ! -e "$d/.git" ]; then echo "  $n: NOT A REPO"; continue; fi
    r=$(git -C "$d" remote 2>/dev/null | head -1)
    if [ -z "$r" ]; then echo "  $n: NO REMOTE"; continue; fi
    git -C "$d" fetch -q "$r" 2>/dev/null
    u=$(git -C "$d" log --branches --not --remotes --oneline 2>/dev/null | wc -l)
    echo "  $n: remote=$r unpushed=$u"
  done'
done
echo
echo "Review the listing above. Any NOT A REPO, NO REMOTE, or unpushed>0 fails the gate."
EOF
chmod +x /tmp/assert-durable.sh
```

- [ ] **Step 2: Run it**

Run: `/tmp/assert-durable.sh`
Expected: every line shows a remote and `unpushed=0`. `ni-tests` on rafik will
report `NOT A REPO` — that is expected and is resolved in Task 17; no other entry
may fail.

- [ ] **Step 3: Do not proceed on any failure**

Any other `NO REMOTE` or `unpushed>0` means data exists in one place only. Return
to the relevant task. From here on the plan begins moving and deleting things.

---

## Task 15: Bring rafik's roster up to date

**Files:**
- Modify: `rafik:~/projects/emanix` (pull)
- Delete: `rafik:~/projects/datacore-config` (a non-repo `bootstrap/` directory)
- Create: `rafik:~/projects/{datacore-config,fragpaper,mardy,chstr,swc,typ}`

**Interfaces:**
- Consumes: Task 14's gate.
- Produces: rafik holding 10 of the 10 roster projects. Task 18 asserts parity.

- [ ] **Step 1: Pull emanix — it is behind by the installer keys fix**

rafik sits at `a71050e` and does not contain `4e1197d` (spec R1). Its working tree
usually has an uncommitted file, so check before pulling.

```bash
ssh rafik 'cd ~/projects/emanix && git status --porcelain; git fetch -q origin && git status -sb | head -2'
```

If a file is modified, report it to Scott and ask whether to stash. Then:

```bash
ssh rafik 'cd ~/projects/emanix && git pull --ff-only origin main 2>&1 | tail -3; git log --oneline -1'
```
Expected: fast-forward, and `git log --all --oneline | grep "carried the keys"` now
finds `4e1197d`.

- [ ] **Step 2: Replace the fake datacore-config**

`rafik:~/projects/datacore-config` is a bare `bootstrap/` directory with no `.git`
— it is not a clone. Confirm that, then replace it.

```bash
ssh rafik 'ls -A ~/projects/datacore-config; test -e ~/projects/datacore-config/.git && echo "IS A REPO — STOP" || echo "not a repo, safe to replace"'
```

Only if that prints `not a repo, safe to replace`:

```bash
ssh rafik 'mv ~/projects/datacore-config ~/projects/.datacore-config-old && git clone -q git@github.com:scott-whitson/datacore-config.git ~/projects/datacore-config && echo cloned && diff -rq ~/projects/.datacore-config-old ~/projects/datacore-config/bootstrap 2>&1 | head -10'
```

Review the diff. If the old directory holds anything the clone lacks, surface it to
Scott. Once satisfied: `ssh rafik 'rm -rf ~/projects/.datacore-config-old'`.

- [ ] **Step 3: Clone the five newly-published repos**

```bash
ssh rafik 'cd ~/projects && for r in fragpaper mardy chstr swc typ; do
  [ -e "$r" ] && { echo "$r exists, skipping"; continue; }
  git clone -q git@github.com:scott-whitson/$r.git && echo "cloned $r"
done'
```

- [ ] **Step 4: Verify each clone is healthy**

```bash
ssh rafik 'for r in datacore-config fragpaper mardy chstr swc typ; do printf "%-16s " $r; git -C ~/projects/$r log --oneline -1 2>&1 | head -1; done; echo; du -sh ~/projects | tail -1; df -h /home | tail -1'
```
Expected: each prints a commit. Disk growth on rafik should be roughly 100M-150M
after ignores; it has 179G free.

---

## Task 16: Bring datacore's roster up to date

**Files:**
- Create: `datacore:~/projects/{emanix,scottwhitson.com}`

**Interfaces:**
- Consumes: Task 14's gate.
- Produces: datacore holding 10 of the 10 roster projects. Task 18 asserts parity.

- [ ] **Step 1: Clone the two rafik-only projects**

```bash
ssh datacore 'cd ~/projects && for r in emanix scottwhitson.com; do
  [ -e "$r" ] && { echo "$r exists, skipping"; continue; }
  git clone -q git@github.com:scott-whitson/$r.git && echo "cloned $r"
done'
```

- [ ] **Step 2: Verify**

```bash
ssh datacore 'for r in emanix scottwhitson.com; do printf "%-18s " $r; git -C ~/projects/$r log --oneline -1; done'
```
Expected: `emanix` at the current `origin/main` (which now includes this plan and
spec), `scottwhitson.com` at its head.

Note: datacore now has an emanix clone of its own. The relay recipe in Task 0 still
creates and deletes a temporary bare clone in `/tmp` and does **not** use this one.

---

## Task 17: Resolve ni-tests

**Files:**
- Delete or relocate: `rafik:~/projects/ni-tests` (12K, three loose elisa test files, not a repo)

**Interfaces:**
- Consumes: Task 15.
- Produces: `~/projects` containing only roster entries, so Task 18's parity check can be exact.

- [ ] **Step 1: Show Scott the contents**

```bash
ssh rafik 'ls -la ~/projects/ni-tests; for f in ~/projects/ni-tests/*; do echo "=== $f ==="; head -20 "$f"; done'
```

The three files are `test-elisa-init.el`, `test-elisa-search.el`, `test-vec0.el` —
scratch tests for `elisa`, which is a roster project with a GitHub remote.

- [ ] **Step 2: Ask Scott to choose**

Either fold them into `elisa`'s test directory and commit them there, or delete
them. They are 12K of scratch; there is no third sensible option, and leaving them
in place would fail Task 18.

- [ ] **Step 3a: If folding into elisa**

```bash
ssh rafik 'cd ~/projects/elisa && ls tests 2>/dev/null || ls'
```
Place them where `elisa`'s existing tests live, then:
```bash
ssh rafik 'cd ~/projects/elisa && git add -A && git commit -q -m "tests: import scratch tests from ~/projects/ni-tests

These lived as loose files in a non-repo directory outside any project. They
belong with elisa." && git push origin $(git rev-parse --abbrev-ref HEAD) 2>&1 | tail -2 && rm -rf ~/projects/ni-tests && echo removed'
```

- [ ] **Step 3b: If deleting**

```bash
ssh rafik 'rm -rf ~/projects/ni-tests && echo removed'
```

- [ ] **Step 4: Verify**

Run: `ssh rafik 'test -e ~/projects/ni-tests && echo "STILL PRESENT" || echo "gone"'`
Expected: `gone`

---

## Task 18: GATE — roster parity

**Files:**
- Create: `/tmp/assert-roster-parity.sh`

**Interfaces:**
- Consumes: Tasks 15-17.
- Produces: proof that rafik and datacore hold the same personal projects.

- [ ] **Step 1: Write the check**

```bash
cat > /tmp/assert-roster-parity.sh <<'EOF'
#!/bin/bash
# rafik and datacore must hold the same personal projects.
# Excluded by design: work (synced, not personal), websites.git (an origin,
# datacore-only), _archive and archive (relocated in Task 19).
set -uo pipefail
list() { ssh "$1" 'cd ~/projects && ls -1 | grep -vxE "work|websites.git|_archive|archive|\.stfolder|\.stignore|\.claude"' | sort; }
list rafik > /tmp/roster-rafik.txt
list datacore > /tmp/roster-datacore.txt
echo "rafik:    $(wc -l < /tmp/roster-rafik.txt) projects"
echo "datacore: $(wc -l < /tmp/roster-datacore.txt) projects"
if diff -u /tmp/roster-rafik.txt /tmp/roster-datacore.txt; then
  echo "PASS: rosters identical"; exit 0
fi
echo "FAIL: rosters differ (see diff above)"; exit 1
EOF
chmod +x /tmp/assert-roster-parity.sh
```

- [ ] **Step 2: Run it**

Run: `/tmp/assert-roster-parity.sh`
Expected: both hosts report 10 projects, `PASS: rosters identical`. The 10 are
`chstr datacore-config elisa emanix fragpaper mardy minne scottwhitson.com swc typ`.

- [ ] **Step 3: Reconcile any difference before proceeding**

A name on one side only means a clone was missed (Task 15/16) or something new
appeared. Do not adjust the exclusion list to make the check pass.

---

## Task 19: Move datacore's archive out of $HOME

**Files:**
- Move: `datacore:~/projects/_archive` → `/srv/data/_archive/projects/`
- Move: `datacore:~/projects/archive/waybar` → `/srv/data/_archive/projects/`

**Interfaces:**
- Consumes: Task 5's backup gate, Task 18's parity gate.
- Produces: `~/projects` on datacore containing only roster entries plus `work` and `websites.git`.

`/srv/data` is a symlink to `/home/srv-data`, so source and destination share the
`/home` filesystem: this is an atomic rename, not a 6.5G copy. `_archive` is not in
the backup excludes, so the destination is inside the Task 1 selection.

- [ ] **Step 1: Confirm same-filesystem and record the source state**

```bash
ssh datacore 'stat -c "%d %n" /home/scott/projects/_archive /home/srv-data; echo "--- source ---"; du -sh ~/projects/_archive; ls -A ~/projects/_archive; find ~/projects/_archive -type f | wc -l'
```
Expected: the same device number for both paths. **If the device numbers differ,
stop** — it becomes a 6.5G copy with a half-moved window, and needs `rsync
--remove-source-files` with its own verification instead.

Record the file count; Step 4 compares against it.

- [ ] **Step 2: Create the destination and move**

```bash
ssh datacore 'mkdir -p /srv/data/_archive/projects && mv ~/projects/_archive/* /srv/data/_archive/projects/ && rmdir ~/projects/_archive && echo moved'
```

- [ ] **Step 3: Move the small waybar archive in with it**

```bash
ssh datacore 'mv ~/projects/archive/waybar /srv/data/_archive/projects/waybar && rmdir ~/projects/archive && echo moved'
```
If `rmdir` fails, `~/projects/archive` held more than `waybar` — list it and report
rather than forcing.

- [ ] **Step 4: Verify nothing was lost**

```bash
ssh datacore 'echo "--- destination ---"; du -sh /srv/data/_archive/projects; ls -A /srv/data/_archive/projects; find /srv/data/_archive/projects -type f | wc -l; echo "--- source gone? ---"; ls -d ~/projects/_archive ~/projects/archive 2>&1'
```
Expected: destination size ~6.5G, the file count matches Step 1 plus waybar's, and
both source paths report "No such file or directory".

- [ ] **Step 5: Prove it is actually backed up**

Per the spec, verify against a real snapshot rather than by reading config — Phase
0A found the config claim was worthless.

```bash
ssh datacore 'python3 -c "
import json,urllib.request
r=urllib.request.Request(\"http://127.0.0.1:9898/v1.Backrest/Backup\",
  data=json.dumps({\"value\":\"datacore-daily\"}).encode(),
  headers={\"Content-Type\":\"application/json\"})
print(urllib.request.urlopen(r).status)"'
```

Wait for completion, then list the path inside the newest snapshot:

```bash
ssh datacore 'sudo -n bash -c "source /etc/restic/b2.env; RESTIC_REPOSITORY=b2:scott-data-restic:/ RESTIC_PASSWORD_FILE=/etc/restic/password /home/scott/.local/share/backrest/restic ls latest /srv/data/_archive/projects 2>/dev/null | head -10"'
```
Expected: entries under `/srv/data/_archive/projects`. An empty result means the
archive is not captured — investigate the plan's paths and excludes before
treating this task as done.

---

## Task 20: Retire work_sync.sh

**Files:**
- Delete: `datacore:~/projects/datacore-config/scripts/work_sync.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: a `datacore-config` that can no longer regenerate `~/work`.

`~/work` (847M) is a strict subset of `~/projects/work` — the destination of a
one-way rsync mirror superseded by the Syncthing `work-projects` folder. Per spec
D5 the directory itself is left in place and simply not migrated; the script must
go, or any run recreates it.

- [ ] **Step 1: Confirm nothing invokes it**

```bash
ssh datacore 'grep -rn "work_sync" ~/projects/datacore-config --include="*.sh" --include="*.md" --include="*.service" --include="*.timer" | grep -v "scripts/work_sync.sh:"; echo "--- systemd ---"; systemctl list-unit-files | grep -i work; echo "--- cron ---"; crontab -l 2>/dev/null | grep -i work; echo "(empty output above means nothing invokes it)"'
```

If a unit, timer or cron entry references it, remove that first and note it.

- [ ] **Step 2: Delete and commit**

```bash
ssh datacore 'cd ~/projects/datacore-config && git rm -q scripts/work_sync.sh && git commit -q -m "scripts: drop work_sync.sh, superseded by Syncthing work-projects

This was a one-way rsync mirror of the work laptop projects tree into ~/work,
replaced by the Syncthing work-projects folder shared whistle<->datacore<->rafik.
It still shipped, so any run would recreate the stale 847M ~/work subset. The
directory itself is left alone and will not be migrated at cutover." && git push origin master 2>&1 | tail -2'
```

- [ ] **Step 3: Verify**

Run: `ssh datacore 'test -e ~/projects/datacore-config/scripts/work_sync.sh && echo "STILL PRESENT" || echo gone; ls -d ~/work'`
Expected: `gone`, and `~/work` still present — that is intended.

---

## Task 21: Remove only the vestigial Syncthing folder

**Files:**
- Modify: datacore Syncthing config, via its REST API

**Interfaces:**
- Consumes: nothing.
- Produces: datacore serving six folders instead of seven.

**Remove `default` → `~/Sync` only.** `websites` and `work-docs` are whistle's peer
pairs and its only route to the work vault and the websites tree — verified from
whistle's own config, both shared `whistle <-> datacore`, and whistle does not sync
`~/docs` as a whole. Deleting them breaks whistle.

- [ ] **Step 1: Confirm `default` is shared with nobody**

```bash
ssh datacore 'python3 - <<PY
import xml.etree.ElementTree as ET
r = ET.parse("/home/scott/.local/state/syncthing/config.xml").getroot()
devs = {d.get("id"): d.get("name") for d in r.findall("device")}
for f in r.findall("folder"):
    peers = [devs.get(d.get("id"), d.get("id")[:7]) for d in f.findall("device")]
    print("%-16s %-34s peers=%s" % (f.get("id"), f.get("path"), peers))
PY'
```
Expected: `default /home/scott/Sync peers=['"'"'datacore'"'"']` — itself only. If any
other device appears, stop and report.

- [ ] **Step 2: Remove it through the API**

Editing `config.xml` while Syncthing runs is pointless; it rewrites the file.

```bash
ssh datacore 'key=$(python3 -c "
import xml.etree.ElementTree as ET
print(ET.parse(\"/home/scott/.local/state/syncthing/config.xml\").getroot().find(\"gui/apikey\").text)")
curl -s -X DELETE -H "X-API-Key: $key" http://127.0.0.1:8384/rest/config/folders/default -w "\nHTTP %{http_code}\n"'
```
Expected: `HTTP 200`.

- [ ] **Step 3: Verify the remaining six**

Re-run Step 1's lister.
Expected: `docs`, `downloads`, `pi-agent`, `websites`, `work-docs`, `work-projects`
— six folders, `default` gone, **`websites` and `work-docs` still present**.

- [ ] **Step 4: Confirm whistle is unaffected**

```bash
curl -s -H "X-API-Key: $(python3 -c 'import xml.etree.ElementTree as ET; print(ET.parse("/home/scott/.local/state/syncthing/config.xml").getroot().find("gui/apikey").text)')" \
  http://127.0.0.1:8384/rest/db/status?folder=work-docs | python3 -m json.tool | grep -E 'state|globalFiles|errors'
```
Expected: `state` is `idle`, `errors` is `0`. Run the same for `websites`. A folder
in `unshared` or error state means Step 2 hit the wrong id — restore from
`config.json.bak` equivalents and re-check.

- [ ] **Step 5: Optionally remove the now-unused directory**

`~/Sync` holds only a `.stfolder` marker. Per spec D5 datacore's cosmetic tidying is
skipped, so leaving it is correct. Do not delete it.

---

## Task 22: Exclude clients from sync, in the emanix repo

**Files:**
- Modify: `whistle:~/projects/emanix/ioshi/i-intelligence/syncthing.nix` (or wherever `projects/.stignore` is generated)

**Interfaces:**
- Consumes: nothing.
- Produces: `/clients` in whistle's `~/projects/.stignore`. Task 23 depends on this being live *before* the move.

**Order is load-bearing.** `~/projects/.stignore` is a home-manager symlink into the
nix store, so it cannot be edited in place — the change goes in the emanix repo,
gets rebuilt, and only then does Task 23 move the directory. Reversed, Syncthing
replicates 4.4G of client data to rafik and datacore the moment it lands.

- [ ] **Step 1: Find where the .stignore content is defined**

```bash
cd ~/projects/emanix && grep -rn "stignore" --include="*.nix" . | head; echo "--- current live file ---"; cat ~/projects/.stignore
```

- [ ] **Step 2: Write the failing assertion**

```bash
cat > /tmp/assert-clients-ignored.sh <<'EOF'
#!/bin/bash
# PASS if whistle's projects/.stignore excludes /clients.
set -uo pipefail
grep -qx "/clients" ~/projects/.stignore && { echo "PASS: /clients ignored"; exit 0; }
echo "FAIL: /clients not in ~/projects/.stignore"; cat ~/projects/.stignore; exit 1
EOF
chmod +x /tmp/assert-clients-ignored.sh
/tmp/assert-clients-ignored.sh
```
Expected: `FAIL: /clients not in ~/projects/.stignore`

- [ ] **Step 3: Add the entry with a comment explaining why**

Alongside the existing `/emanix` exclusion, which has the same rationale:

```
// Work client data — 4.4G, whistle-only by policy. It lives under ~/projects
// to satisfy the four-directory home rule, not to be replicated to personal
// machines. work_sync.sh excluded it for the same reason before it was retired.
/clients
```

- [ ] **Step 4: Commit and relay-push**

```bash
cd ~/projects/emanix && git add -A && git commit -q -m "syncthing: exclude /clients from the work-projects share

~/clients moves under ~/projects to satisfy the four-directory home rule. It is
4.4G of work client data and must not replicate to rafik or datacore, so it is
ignored the same way /emanix is. The retired work_sync.sh excluded clients/ for
the same reason."
```
Then push via the Task 0 relay, and `git fetch origin` before reading status.

- [ ] **Step 5: Rebuild whistle and re-assert**

Rebuild whistle's home-manager/NixOS generation so the store symlink updates, then:

Run: `/tmp/assert-clients-ignored.sh`
Expected: `PASS: /clients ignored`

- [ ] **Step 6: Confirm Syncthing actually reloaded the pattern**

```bash
key=$(python3 -c 'import xml.etree.ElementTree as ET; print(ET.parse("/home/scott/.local/state/syncthing/config.xml").getroot().find("gui/apikey").text)')
curl -s -H "X-API-Key: $key" "http://127.0.0.1:8384/rest/db/ignores?folder=work-projects" | python3 -m json.tool
```
Expected: the returned `ignore` list contains `/clients`. A stale list means
Syncthing has not re-read the file — restart it before Task 23. **Do not proceed to
Task 23 until `/clients` appears here.**

---

## Task 23: Move clients under projects

**Files:**
- Move: `whistle:~/clients` → `whistle:~/projects/clients`

**Interfaces:**
- Consumes: Task 22, verified live.
- Produces: a whistle home with exactly the four permitted directories.

- [ ] **Step 1: Re-confirm the guard**

Run: `/tmp/assert-clients-ignored.sh && curl -s -H "X-API-Key: $(python3 -c 'import xml.etree.ElementTree as ET; print(ET.parse("/home/scott/.local/state/syncthing/config.xml").getroot().find("gui/apikey").text)')" "http://127.0.0.1:8384/rest/db/ignores?folder=work-projects" | grep -c '"/clients"'`
Expected: `PASS`, then a count of at least 1. **If either fails, stop.**

- [ ] **Step 2: Record the source state**

```bash
du -sh ~/clients; ls -A ~/clients; find ~/clients -type f | wc -l
```
Expected: 4.4G, six entries (`archive athens demo-trn rubber tng vesco`).

- [ ] **Step 3: Move it**

```bash
mv ~/clients ~/projects/clients && echo moved && du -sh ~/projects/clients && find ~/projects/clients -type f | wc -l
```
Both filesystems are the same (`/`), so this is a rename. The file count must match
Step 2.

- [ ] **Step 4: Confirm it did not replicate**

Wait two minutes for a Syncthing scan, then:

```bash
for h in rafik datacore; do printf "%-9s " $h; ssh $h 'test -e ~/projects/work/clients && echo "LEAKED — clients replicated!" || echo "clean"'; done
```
Expected: both `clean`. If either leaked, stop immediately, delete the remote copy,
and revisit Task 22 — this is the failure the ordering exists to prevent.

- [ ] **Step 5: Confirm the share is still healthy**

```bash
key=$(python3 -c 'import xml.etree.ElementTree as ET; print(ET.parse("/home/scott/.local/state/syncthing/config.xml").getroot().find("gui/apikey").text)')
curl -s -H "X-API-Key: $key" "http://127.0.0.1:8384/rest/db/status?folder=work-projects" | python3 -m json.tool | grep -E 'state|errors|needFiles'
```
Expected: `state` `idle`, `errors` `0`.

---

## Task 24: Clear whistle's stray tarball

**Files:**
- Delete: `whistle:~/quarterly-snapshot-2026-08-13.tar.gz` (3.4M)

**Interfaces:**
- Consumes: Task 23.
- Produces: whistle's home holding exactly `docs`, `dotfiles`, `downloads`, `projects`.

- [ ] **Step 1: Check whether its content is already preserved**

The quarterly tracker lives at `~/docs/org/work/Quarterly/YYYY-QN.org`, inside the
synced `work-docs` folder.

```bash
tar tzf ~/quarterly-snapshot-2026-08-13.tar.gz | head -20
ls -la ~/docs/org/work/Quarterly/ 2>/dev/null
```

- [ ] **Step 2: Ask Scott, then act**

If the tarball's contents are already in the synced Quarterly directory, delete it.
If it holds anything not otherwise preserved, move it to
`/srv/data/_archive/projects/` on datacore instead — which Task 19 verified is
backed up.

```bash
# only after Scott confirms
rm ~/quarterly-snapshot-2026-08-13.tar.gz && echo removed
```

- [ ] **Step 3: Verify whistle's home**

```bash
ls -A ~ | grep -vE '^\.' | sort
```
Expected exactly: `docs`, `dotfiles`, `downloads`, `projects`

---

## Task 25: Tidy rafik's home

**Files:**
- Move: `rafik:~/org/gdocs/Whitsgrove-Shared-Living-Document.org` → `rafik:~/docs/org/`
- Delete: `rafik:~/org`, `rafik:~/tmp`, `rafik:~/ventoy-setup`
- **Keep:** `rafik:~/emanix-installer.iso`

**Interfaces:**
- Consumes: nothing.
- Produces: rafik's home holding exactly the four permitted directories plus the retained ISO.

- [ ] **Step 1: Move the org file into the synced org tree**

It is an org file; `~/docs/org` is where it belongs and it will then replicate to
datacore.

```bash
ssh rafik 'ls -la ~/org/gdocs/; test -e ~/docs/org/Whitsgrove-Shared-Living-Document.org && echo "DESTINATION EXISTS — compare first" || mv ~/org/gdocs/Whitsgrove-Shared-Living-Document.org ~/docs/org/ && echo moved'
```

If the destination already exists, diff the two and ask Scott which to keep.

- [ ] **Step 2: Remove the empty org tree**

```bash
ssh rafik 'find ~/org -type f | wc -l; rmdir ~/org/gdocs ~/org && echo "org removed"'
```
Expected: file count `0`, then `org removed`. If `rmdir` refuses, something remains
— list it rather than using `rm -rf`.

- [ ] **Step 3: Confirm the org file reached datacore**

```bash
sleep 60; ssh datacore 'ls -la ~/docs/org/Whitsgrove-Shared-Living-Document.org'
```
Expected: the file is present. This also confirms the `docs` folder is syncing.

- [ ] **Step 4: Remove the ventoy scratch**

```bash
ssh rafik 'du -sh ~/tmp ~/ventoy-setup; rm -rf ~/tmp ~/ventoy-setup && echo removed'
```
24M, refetchable. `~/tmp/ventoy-bin` was a PATH shim for the Ventoy installer.

- [ ] **Step 5: Do NOT delete the ISO — verify it is still there**

```bash
ssh rafik 'ls -la ~/emanix-installer.iso'
```
Expected: present. Per spec R1 it is a known-bad pubs-only image retained as the
rebuild baseline. Delete it only once a verified keys-carrying replacement exists.

- [ ] **Step 6: Verify rafik's home**

```bash
ssh rafik 'ls -A ~ | grep -vE "^\." | sort'
```
Expected: `docs`, `dotfiles`, `downloads`, `emanix-installer.iso`, `projects` — the
four directories plus the deliberately retained ISO.

---

## Task 26: Codify — drift check and the NixOS import

**Files:**
- Create: `whistle:~/projects/emanix/bin/home-drift-check.sh`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: a re-runnable check, and confirmation the new datacore inherits the rule.

- [ ] **Step 1: Write the check**

```bash
cat > ~/projects/emanix/bin/home-drift-check.sh <<'EOF'
#!/usr/bin/env bash
# home-drift-check — assert the three-node home model holds.
# 1. every host's $HOME has only docs/dotfiles/downloads/projects
# 2. rafik and datacore hold the same personal projects
# Exceptions are listed explicitly so that adding one is a visible decision.
set -uo pipefail
ALLOWED='docs dotfiles downloads projects'
# rafik keeps emanix-installer.iso until a verified replacement exists (spec R1).
declare -A EXTRA=( [rafik]='emanix-installer.iso' [datacore]='' [whistle]='' )
fail=0
for h in rafik datacore whistle; do
  echo "== $h =="
  if [ "$h" = whistle ]; then entries=$(ls -A ~ | grep -vE '^\.'); else entries=$(ssh "$h" "ls -A ~ | grep -vE '^\.'"); fi
  for e in $entries; do
    case " $ALLOWED ${EXTRA[$h]} " in *" $e "*) ;; *) echo "  STRAY: $e"; fail=1;; esac
  done
  [ "$fail" -eq 0 ] && echo "  clean"
done
echo "== roster parity =="
list() { ssh "$1" 'cd ~/projects && ls -1 | grep -vxE "work|websites.git|\.stfolder|\.stignore|\.claude"' | sort; }
if diff -u <(list rafik) <(list datacore); then echo "  identical"; else echo "  DRIFT"; fail=1; fi
[ "$fail" -eq 0 ] && { echo; echo "PASS"; exit 0; }
echo; echo "FAIL"; exit 1
EOF
chmod +x ~/projects/emanix/bin/home-drift-check.sh
```

Note this excludes `_archive` and `archive` from parity because Task 19 removed
them from `~/projects` entirely — if either reappears there it should show as a
stray project, which it will.

- [ ] **Step 2: Run it**

Run: `~/projects/emanix/bin/home-drift-check.sh`
Expected: `clean` for all three hosts, `identical` rosters, `PASS`. whistle's
`~/projects/clients` is inside `projects` so it does not appear as a stray.

- [ ] **Step 3: Confirm the NixOS datacore inherits the four-directory rule**

```bash
cd ~/projects/emanix && grep -rn "i-intelligence" --include="*.nix" hosts/ profiles/ lib/ 2>/dev/null | grep -i datacore
grep -rn "xdg.nix\|i-intelligence" --include="*.nix" . | grep -v "^./ioshi/i-intelligence" | head
```

Verify the `datacore` NixOS configuration imports `ioshi/i-intelligence` (and hence
`xdg.nix`). If it does not, that is the difference between the new box being clean
by construction and repeating Debian datacore's `Projects`/`Music`/`Pictures`/`Videos`
cruft — add the import and note it for the cutover.

- [ ] **Step 4: Commit and relay-push**

```bash
cd ~/projects/emanix && git add bin/home-drift-check.sh && git commit -q -m "bin: home-drift-check — assert the three-node home model holds

Checks that every host's \$HOME holds only docs/dotfiles/downloads/projects, and
that rafik and datacore hold the same personal projects. Exceptions are listed
explicitly so adding one is a visible decision rather than a quiet drift."
```
Then push via the Task 0 relay, and `git fetch origin` before reading status.

- [ ] **Step 5: Final report**

State plainly which tasks completed, which were skipped and why, and the outcome of
each gate. Per spec D5 the following are **intentionally left in place** on Debian
datacore and must be reported as deliberate, not missed: `~/work`,
`~/dotfiles-usb-snapshot`, `~/Downloads` (capital), `~/Projects`, `~/Music`,
`~/Pictures`, `~/Videos`, `~/Sync`, the pre-home-manager dotfiles, and the loose
logs and tarballs. They are not migrated at cutover.

---

## Self-review notes

**Spec coverage.** D1 → Tasks 6, 9-16. D2 → Task 19. D3 → Tasks 7, 11-13. D4 →
Tasks 22-23. D5 → Tasks 20-21, 26 Step 5. D6 → Tasks 1-5. Roster table → Tasks
8-17. `websites.git` exemption → honoured by exclusion in Tasks 14, 18, 26. Syncthing
section → Task 21. Phases 0A/0/1/2/3/4/5/6/7 → Tasks 1-5 / 6-7 / 8-14 / 15-18 / 19 /
20-21 / 22-24 / 25 / 26. R1 → Task 15 Step 1, Task 25 Step 5. R2 → Task 7 Steps 1-2.
R3 → Tasks 22-23 ordering. R4 → Task 8. R5 → Task 6 Step 3, Task 13 Step 1. R6 →
Task 3.

**Deliberately requires Scott, not automatable:** Task 6 (repo creation — `gh`
authenticated nowhere), Task 7 Step 4 (the stockfish and manim/static calls), Task 8
Steps 2-4 (minne's dirty files and push direction), Task 17 Step 2, Task 24 Step 2.

**Known gap.** Task 4 Step 4 describes the Comsat patch rather than supplying it,
because `comsat-health-backup.sh` has not been read — it is on a host reachable only
through rafik. Read it in Step 1 and write the patch against what is actually there.
This is the one place in the plan where the implementation is specified by intent
instead of by diff, and it is deliberate: guessing at a monitoring script's internals
is how defect 2 was introduced.
