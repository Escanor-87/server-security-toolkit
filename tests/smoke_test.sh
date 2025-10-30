#!/usr/bin/env bash
# Comprehensive smoke test for Server Security Toolkit
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

pass() { 
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

warn() { 
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((TESTS_WARNED++))
}

fail() { 
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

section() {
    echo
    echo -e "${BLUE}══════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}══════════════════════════════════════════${NC}"
}

# Change to script directory
cd "$(dirname "$0")/.." || exit 1

section "1. ENVIRONMENT CHECKS"

# 1.1) Check bash version
if bash --version >/dev/null 2>&1; then
    BASH_VERSION=$(bash --version | head -1)
    pass "bash present: $BASH_VERSION"
else
    fail "bash not found"
fi

# 1.2) Check required tools
for t in ssh systemctl sed grep awk find stat; do
    if command -v "$t" >/dev/null 2>&1; then 
        pass "$t present"
    else 
        warn "$t missing"
    fi
done

# 1.3) Check optional tools
for t in ufw fail2ban-client git curl wget; do
    if command -v "$t" >/dev/null 2>&1; then
        pass "$t available (optional)"
    else
        warn "$t not installed (optional)"
    fi
done

section "2. FILE STRUCTURE VALIDATION"

# 2.1) Check main files exist
for file in main.sh install.sh LICENSE README.md CHANGELOG.md CONTRIBUTING.md; do
    if [[ -f "$file" ]]; then
        pass "$file exists"
    else
        fail "$file missing"
    fi
done

# 2.2) Check modules directory
if [[ -d "modules" ]]; then
    pass "modules/ directory exists"
    for module in ssh_security.sh firewall.sh system_hardening.sh; do
        if [[ -f "modules/$module" ]]; then
            pass "modules/$module exists"
        else
            fail "modules/$module missing"
        fi
    done
else
    fail "modules/ directory missing"
fi

# 2.3) Check configs directory
if [[ -d "configs" ]]; then
    pass "configs/ directory exists"
    if [[ -f "configs/defaults.env" ]]; then
        pass "configs/defaults.env exists"
    else
        warn "configs/defaults.env missing"
    fi
else
    warn "configs/ directory missing"
fi

section "3. SHELLCHECK LINTING"

# 3.1) Run shellcheck if available
if command -v shellcheck >/dev/null 2>&1; then
    echo "Running shellcheck on main.sh..."
    if shellcheck -x main.sh 2>/dev/null; then
        pass "main.sh passes shellcheck"
    else
        warn "main.sh has shellcheck warnings"
    fi
    
    echo "Running shellcheck on modules..."
    module_errors=0
    for module in modules/*.sh; do
        if [[ -f "$module" ]]; then
            if shellcheck -x "$module" 2>/dev/null; then
                pass "$(basename "$module") passes shellcheck"
            else
                warn "$(basename "$module") has shellcheck warnings"
                ((module_errors++))
            fi
        fi
    done
    
    if [[ $module_errors -eq 0 ]]; then
        pass "All modules pass shellcheck"
    else
        warn "$module_errors module(s) have shellcheck warnings"
    fi
else
    warn "shellcheck not installed; skipping lint checks"
fi

section "4. CODE QUALITY CHECKS"

# 4.1) Check for dangerous patterns
echo "Checking for dangerous patterns..."
if grep -rn "rm -rf /" . --exclude-dir=.git 2>/dev/null; then
    fail "Found dangerous 'rm -rf /' pattern"
else
    pass "No dangerous 'rm -rf /' patterns found"
fi

# 4.2) Check for hardcoded secrets
if grep -rn "password=" . --exclude-dir=.git --exclude="*.md" 2>/dev/null | grep -v "PasswordAuthentication"; then
    warn "Potential hardcoded password found"
else
    pass "No hardcoded passwords found"
fi

# 4.3) Check set -euo pipefail usage
if grep -q "set -euo pipefail" main.sh; then
    pass "main.sh uses strict mode (set -euo pipefail)"
else
    warn "main.sh missing strict mode"
fi

# 4.4) Check for proper quoting
echo "Checking variable quoting..."
if grep -rn '\$[A-Za-z_][A-Za-z0-9_]*[^"]' modules/*.sh | grep -v '"\$' | grep -v '#' | head -5; then
    warn "Found potentially unquoted variables (may be false positives)"
else
    pass "Variable quoting looks good"
fi

section "5. FUNCTION VALIDATION"

# 5.1) Check critical functions exist in main.sh
for func in get_ssh_port is_port_available log_info log_error log_success; do
    if grep -q "^${func}()" main.sh || grep -q "^${func} ()" main.sh; then
        pass "Function '$func' exists in main.sh"
    else
        fail "Critical function '$func' missing in main.sh"
    fi
done

# 5.2) Check module functions
if grep -q "configure_ssh_security()" modules/ssh_security.sh; then
    pass "SSH security module has main entry function"
else
    fail "SSH security module missing main entry function"
fi

if grep -q "configure_firewall()" modules/firewall.sh; then
    pass "Firewall module has main entry function"
else
    fail "Firewall module missing main entry function"
fi

section "6. SECURITY VALIDATION"

# 6.1) Check backup creation before changes
if grep -q "backup_ssh_config" modules/ssh_security.sh; then
    pass "SSH module creates backups"
else
    warn "SSH module may not create backups"
fi

# 6.2) Check for input validation
if grep -q "read -p" modules/ssh_security.sh && grep -q "if.*=~" modules/ssh_security.sh; then
    pass "SSH module validates user input"
else
    warn "SSH module may lack input validation"
fi

# 6.3) Check UFW race condition fix
if grep -q "# КРИТИЧЕСКИ ВАЖНО: Сначала добавляем новое правило" modules/ssh_security.sh; then
    pass "UFW race condition fix is present"
else
    warn "UFW race condition fix comment missing"
fi

section "7. DOCUMENTATION CHECKS"

# 7.1) Check README completeness
if grep -q "Quick Start" README.md; then
    pass "README has Quick Start section"
else
    warn "README missing Quick Start section"
fi

if grep -q "Installation" README.md || grep -q "Установка" README.md; then
    pass "README has Installation section"
else
    warn "README missing Installation section"
fi

# 7.2) Check LICENSE
if [[ -f LICENSE ]]; then
    if grep -q "MIT License" LICENSE; then
        pass "LICENSE is MIT"
    else
        warn "LICENSE exists but may not be MIT"
    fi
else
    fail "LICENSE file missing"
fi

# 7.3) Check CHANGELOG format
if grep -q "## \[Unreleased\]" CHANGELOG.md; then
    pass "CHANGELOG follows Keep a Changelog format"
else
    warn "CHANGELOG may not follow standard format"
fi

section "8. INTEGRATION CHECKS"

# 8.1) Check git configuration (non-destructive)
if [[ -d .git ]]; then
    pass "Git repository initialized"
    if git remote -v | grep -q "server-security-toolkit"; then
        pass "Git remote configured correctly"
    else
        warn "Git remote may not be configured"
    fi
else
    warn "Not a git repository (expected in development)"
fi

# 8.2) Check file permissions
if [[ -x main.sh ]]; then
    pass "main.sh is executable"
else
    fail "main.sh is not executable"
fi

for module in modules/*.sh; do
    if [[ -x "$module" ]]; then
        pass "$(basename "$module") is executable"
    else
        warn "$(basename "$module") is not executable"
    fi
done

section "9. SYNTAX VALIDATION"

# 9.1) Basic syntax check
echo "Checking bash syntax..."
if bash -n main.sh 2>/dev/null; then
    pass "main.sh has valid bash syntax"
else
    fail "main.sh has syntax errors"
fi

for module in modules/*.sh; do
    if bash -n "$module" 2>/dev/null; then
        pass "$(basename "$module") has valid syntax"
    else
        fail "$(basename "$module") has syntax errors"
    fi
done

section "10. TEST SUMMARY"

echo
echo "════════════════════════════════════════"
echo -e "${GREEN}Tests Passed:  $TESTS_PASSED${NC}"
echo -e "${YELLOW}Tests Warned:  $TESTS_WARNED${NC}"
echo -e "${RED}Tests Failed:  $TESTS_FAILED${NC}"
echo "════════════════════════════════════════"
echo

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}❌ Smoke test FAILED${NC}"
    exit 1
elif [[ $TESTS_WARNED -gt 5 ]]; then
    echo -e "${YELLOW}⚠️  Smoke test PASSED with warnings${NC}"
    exit 0
else
    echo -e "${GREEN}✅ Smoke test PASSED${NC}"
    exit 0
fi
