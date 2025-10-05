#!/usr/bin/env bash
# Simple smoke test for Server Security Toolkit
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# 1) Check bash version
if bash --version >/dev/null 2>&1; then
    pass "bash present"
else
    fail "bash not found"
fi

# 2) Check required tools existence (non-root safe)
for t in ssh systemctl sed grep awk; do
  if command -v "$t" >/dev/null 2>&1; then pass "$t present"; else warn "$t missing"; fi
done

# 3) ShellCheck linting (if available)
if command -v shellcheck >/dev/null 2>&1; then
  echo "Running shellcheck..."
  shellcheck -x ../main.sh || warn "shellcheck warnings in main.sh"
  shellcheck -x ../modules/*.sh || warn "shellcheck warnings in modules"
  pass "shellcheck completed"
else
  warn "shellcheck not installed; skipping lint"
fi

# 4) Static scan of scripts (no mutations)
grep -R "rm -rf /" ../ || pass "no dangerous rm -rf patterns found"

pass "Smoke test finished"
