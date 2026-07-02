#!/usr/bin/env bash
# Run the full RTX-VPN e2e suite across every supported distro (rootful podman).
#   sudo test/matrix.sh [distro1 distro2 ...]
# With no args, runs the full 8-distro matrix.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DISTROS=("$@")
[ ${#DISTROS[@]} -eq 0 ] && DISTROS=(debian12 debian13 ubuntu22 ubuntu24 ubuntu26 fedora arch alma)

GREEN=$'\e[32m'; RED=$'\e[31m'; NC=$'\e[0m'
declare -A OUT
LOGDIR="$REPO/test/logs"; mkdir -p "$LOGDIR"

for d in "${DISTROS[@]}"; do
  echo "================= $d ================="
  if bash "$REPO/test/run.sh" "$d" >"$LOGDIR/$d.log" 2>&1; then
    OUT[$d]="${GREEN}ALL PASS${NC}"
  else
    n=$?; OUT[$d]="${RED}$n FAILED${NC}"
  fi
  # compact per-distro result table from the log
  grep -E '  (PASS|FAIL) ' "$LOGDIR/$d.log" | sed 's/^/    /'
done

echo ""
echo "################ MATRIX RESULT ################"
for d in "${DISTROS[@]}"; do printf '  %-10s %s\n' "$d" "${OUT[$d]}"; done
echo "logs: $LOGDIR/<distro>.log"
