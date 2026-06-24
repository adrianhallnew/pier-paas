#!/usr/bin/env bash
set -euo pipefail

# T1.1–T1.10 smoke tests against the live Pier VM.
# Usage: VM_IP=1.2.3.4 bash scripts/smoke.sh
#        or just: bash scripts/smoke.sh  (reads VM_IP from terraform output)

if [ -z "${VM_IP:-}" ]; then
  VM_IP=$(cd infra && terraform output -raw vm_public_ip 2>/dev/null) || true
fi
if [ -z "${VM_IP:-}" ]; then
  echo "Error: VM_IP not set and 'terraform output vm_public_ip' returned nothing." >&2
  echo "Run 'make apply' first or set VM_IP=<ip> explicitly." >&2
  exit 1
fi

SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ~/.ssh/pier_ed25519 pier@${VM_IP}"

PASS=0
FAIL=0

check() {
  local label="$1" result="$2"
  if [ "$result" = "ok" ]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    PASS=$((PASS + 1))
  else
    printf "  \033[31m✗\033[0m %s — %s\n" "$label" "$result"
    FAIL=$((FAIL + 1))
  fi
}

echo "Pier smoke tests — VM ${VM_IP}"
echo

# T1.1 — Terraform idempotent (second plan reports no changes)
echo "[T1.1] Terraform idempotent..."
PLAN_OUT=$(cd infra && terraform plan -detailed-exitcode 2>&1; echo "exit:$?")
if echo "$PLAN_OUT" | grep -q "exit:0"; then
  check "T1.1 terraform plan no-changes" "ok"
else
  check "T1.1 terraform plan no-changes" "plan shows changes"
fi

# T1.2 — cloud-init done
echo "[T1.2] cloud-init status..."
CI_STATUS=$($SSH sudo cloud-init status --wait 2>&1 || echo "error")
if echo "$CI_STATUS" | grep -q "status: done"; then
  check "T1.2 cloud-init done" "ok"
else
  check "T1.2 cloud-init done" "$CI_STATUS"
fi

# T1.3 — firewall posture (only 22, 80, 443 open)
echo "[T1.3] Firewall posture (nmap)..."
if command -v nmap &>/dev/null; then
  OPEN_PORTS=$(nmap -Pn -p 1-1000 "$VM_IP" 2>/dev/null | grep "^[0-9]" | grep open | awk -F/ '{print $1}' | sort -n | tr '\n' ' ' | xargs)
  if [ "$OPEN_PORTS" = "80 443" ] || [ "$OPEN_PORTS" = "22 80 443" ]; then
    check "T1.3 firewall (ports: $OPEN_PORTS)" "ok"
  else
    check "T1.3 firewall" "unexpected open ports: $OPEN_PORTS"
  fi
else
  check "T1.3 firewall" "SKIP — nmap not installed"
fi

# T1.4 — Docker healthy
echo "[T1.4] Docker hello-world..."
if $SSH docker run --rm hello-world &>/dev/null; then
  check "T1.4 docker hello-world" "ok"
else
  check "T1.4 docker hello-world" "failed"
fi

# T1.5 — Block volume mounted at /var/lib/docker (200 GB)
echo "[T1.5] Block volume mount..."
DF_OUT=$($SSH df -h /var/lib/docker 2>&1 | tail -1)
if echo "$DF_OUT" | grep -qE "1[0-9][0-9]G|200G"; then
  check "T1.5 /var/lib/docker 200G volume" "ok"
else
  check "T1.5 /var/lib/docker 200G volume" "unexpected: $DF_OUT"
fi

# T1.6 — Wildcard TLS responds 200 (staging cert = -k)
echo "[T1.6] Wildcard TLS..."
DOMAIN="${DUCKDNS_ROOT:-}"
if [ -z "$DOMAIN" ] && [ -f .env.local ]; then
  DOMAIN=$(grep DUCKDNS_ROOT .env.local | cut -d= -f2)
fi
if [ -n "$DOMAIN" ]; then
  HTTP_CODE=$(curl -sko /dev/null -w "%{http_code}" "https://smoke-$(date +%s).${DOMAIN}" || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    check "T1.6 wildcard TLS 200 OK" "ok"
  else
    check "T1.6 wildcard TLS" "HTTP $HTTP_CODE (staging cert? use -k)"
  fi
else
  check "T1.6 wildcard TLS" "SKIP — DUCKDNS_ROOT not set"
fi

# T1.7 — Cert chain valid (issued by LE, > 60 days)
echo "[T1.7] Cert validity..."
if [ -n "${DOMAIN:-}" ]; then
  CERT_INFO=$(echo | openssl s_client -connect "${DOMAIN}:443" -servername "x.${DOMAIN}" 2>/dev/null | openssl x509 -noout -issuer -enddate 2>/dev/null || echo "")
  if echo "$CERT_INFO" | grep -qi "let's encrypt\|letsencrypt"; then
    check "T1.7 cert issued by Let's Encrypt" "ok"
  else
    check "T1.7 cert chain" "not Let's Encrypt (staging cert or no cert yet)"
  fi
else
  check "T1.7 cert chain" "SKIP — DUCKDNS_ROOT not set"
fi

# T1.8 — Master key permissions
echo "[T1.8] Master key..."
STAT_OUT=$($SSH sudo stat -c '%a %U' /etc/pier/master.key 2>&1 || echo "error")
if [ "$STAT_OUT" = "400 root" ]; then
  check "T1.8 /etc/pier/master.key 400 root" "ok"
else
  check "T1.8 /etc/pier/master.key" "got: $STAT_OUT"
fi

# T1.9 — Reboot resilience
echo "[T1.9] Reboot resilience..."
$SSH sudo reboot &>/dev/null || true
echo "  Waiting 90s for VM to come back..."
sleep 90
if [ -n "${DOMAIN:-}" ]; then
  HTTP_CODE=$(curl -sko /dev/null -w "%{http_code}" "https://${DOMAIN}" || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    check "T1.9 still 200 OK after reboot" "ok"
  else
    check "T1.9 after reboot" "HTTP $HTTP_CODE"
  fi
else
  check "T1.9 reboot" "SKIP — DUCKDNS_ROOT not set"
fi

# T1.10 — Caddy admin API not public
echo "[T1.10] Caddy admin not public..."
ADMIN_2019=$(curl -ss --max-time 5 "http://${VM_IP}:2019" 2>&1 || echo "refused")
if echo "$ADMIN_2019" | grep -qiE "refused|timed out|couldn't connect|000"; then
  check "T1.10 :2019 not reachable externally" "ok"
else
  check "T1.10 :2019 not reachable externally" "got a response — admin API may be exposed"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
