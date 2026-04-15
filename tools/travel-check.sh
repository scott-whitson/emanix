#!/usr/bin/env bash
# Pre-travel connectivity check: internet -> tailscale -> SSH into remote hosts.
# Run from home wifi AND from phone hotspot before traveling.
set -u

pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAILED=1; }
FAILED=0

echo "== Network =="
ACTIVE=$(nmcli -t -f NAME,TYPE con show --active | grep wireless | cut -d: -f1)
echo "  wifi: ${ACTIVE:-<none>}"
ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 && pass "internet (1.1.1.1)" || fail "internet"
ping -c1 -W2 one.one.one.one >/dev/null 2>&1 && pass "DNS" || fail "DNS"

echo "== Tailscale =="
if ! tailscale status >/dev/null 2>&1; then
  fail "tailscale not running — try: sudo tailscale up"
else
  pass "tailscale up ($(tailscale ip -4))"
fi

echo "== SSH targets =="
# host:friendly-name pairs — edit as needed
TARGETS=(
  "minne:home server (minne/malt)"
  "swhitson-11l-1:work laptop (linux)"
)
for entry in "${TARGETS[@]}"; do
  host="${entry%%:*}"
  label="${entry#*:}"
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
        "$host" "echo ok" 2>/dev/null | grep -q ok; then
    pass "ssh $host — $label"
  else
    fail "ssh $host — $label"
  fi
done

echo
[ $FAILED -eq 0 ] && echo "ALL GOOD ✈️" || { echo "FAILURES — fix before you fly"; exit 1; }
