#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

check() {
  local label="$1"
  local result="$2"
  if [ "$result" = "ok" ]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    PASS=$((PASS + 1))
  else
    printf "  \033[31m✗\033[0m %s — %s\n" "$label" "$result"
    FAIL=$((FAIL + 1))
  fi
}

version_gte() {
  local have="$1" want="$2"
  printf '%s\n%s\n' "$want" "$have" | sort -V -C
}

echo "Pier doctor — checking prerequisites"
echo

# 1. terraform >= 1.7
TF_VER=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || echo "")
if [ -n "$TF_VER" ] && version_gte "$TF_VER" "1.7.0"; then
  check "terraform >= 1.7 ($TF_VER)" "ok"
else
  check "terraform >= 1.7" "not found or too old (${TF_VER:-missing})"
fi

# 2. node >= 22
NODE_VER=$(node -v 2>/dev/null | tr -d 'v' || echo "")
if [ -n "$NODE_VER" ] && version_gte "$NODE_VER" "22.0.0"; then
  check "node >= 22 ($NODE_VER)" "ok"
else
  check "node >= 22" "not found or too old (${NODE_VER:-missing})"
fi

# 3. pnpm >= 9
PNPM_VER=$(pnpm -v 2>/dev/null || echo "")
if [ -n "$PNPM_VER" ] && version_gte "$PNPM_VER" "9.0.0"; then
  check "pnpm >= 9 ($PNPM_VER)" "ok"
else
  check "pnpm >= 9" "not found or too old (${PNPM_VER:-missing})"
fi

# 4. docker >= 26
DOCKER_VER=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "")
if [ -n "$DOCKER_VER" ] && version_gte "$DOCKER_VER" "26.0.0"; then
  check "docker >= 26 ($DOCKER_VER)" "ok"
else
  check "docker >= 26" "not found or too old (${DOCKER_VER:-missing})"
fi

# 5. git >= 2.40
GIT_VER=$(git --version 2>/dev/null | awk '{print $3}' || echo "")
if [ -n "$GIT_VER" ] && version_gte "$GIT_VER" "2.40.0"; then
  check "git >= 2.40 ($GIT_VER)" "ok"
else
  check "git >= 2.40" "not found or too old (${GIT_VER:-missing})"
fi

# 6. jq
if command -v jq &>/dev/null; then
  check "jq ($(jq --version))" "ok"
else
  check "jq" "not found"
fi

# 7. curl
if command -v curl &>/dev/null; then
  check "curl" "ok"
else
  check "curl" "not found"
fi

# 8. age
if command -v age &>/dev/null; then
  check "age ($(age --version 2>&1 | head -1))" "ok"
else
  check "age" "not found"
fi

# 9. oci CLI
if command -v oci &>/dev/null; then
  check "oci CLI ($(oci --version 2>&1 | head -1))" "ok"
else
  check "oci CLI" "not found (pip install oci-cli)"
fi

# 10. docker ARM buildx
if docker buildx ls 2>/dev/null | grep -q "linux/arm64"; then
  check "docker ARM buildx (linux/arm64 present)" "ok"
else
  check "docker ARM buildx" "linux/arm64 not in builder list"
fi

# 11. docker without sudo
if docker run --rm hello-world &>/dev/null; then
  check "docker without sudo" "ok"
else
  check "docker without sudo" "failed — run: sudo usermod -aG docker \$USER && newgrp docker"
fi

# 12. OCI auth
if oci iam region list &>/dev/null; then
  check "OCI auth (oci iam region list)" "ok"
else
  check "OCI auth" "failed — check ~/.oci/config and ~/.oci/pier_oci.pem"
fi

# 13. .env.local populated
if [ -f .env.local ]; then
  if grep -qE "CHANGEME|<your|TODO" .env.local; then
    check ".env.local" "contains unfilled placeholders"
  else
    check ".env.local (all keys set)" "ok"
  fi
else
  check ".env.local" "not found — cp .env.example .env.local"
fi

echo
echo "Results: $PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ]
