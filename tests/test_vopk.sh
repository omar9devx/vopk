#!/usr/bin/env bash
# Automated Test Suite for VOPK
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VOPK="${SCRIPT_DIR}/src/vopk.sh"
VOPK_BIN="${SCRIPT_DIR}/bin/vopk"
SHELL2BIN="${SCRIPT_DIR}/bin/shell2bin.py"

PASSED=0
FAILED=0

run_test() {
    local name="$1"; shift
    printf "[TEST] %-45s ... " "$name"
    if "$@" >/dev/null 2>&1; then
        printf "\033[0;32mPASSED\033[0m\n"
        ((PASSED++)) || true
    else
        printf "\033[0;31mFAILED\033[0m\n"
        ((FAILED++)) || true
    fi
}

echo "=================================================="
echo " Running VOPK Test Suite"
echo "=================================================="

# 1. Syntax checks
run_test "Bash syntax check (src/vopk.sh)" bash -n "$VOPK"
run_test "POSIX sh syntax (src/installscript.sh)" sh -n "${SCRIPT_DIR}/src/installscript.sh"
run_test "POSIX sh syntax (src/updatescript.sh)" sh -n "${SCRIPT_DIR}/src/updatescript.sh"

# 2. CLI options
run_test "vopk --version" bash "$VOPK" --version
run_test "vopk --help" bash "$VOPK" --help
run_test "vopk --no-color --help" bash "$VOPK" --no-color --help

# 3. System info & diagnostics
run_test "vopk doctor" bash "$VOPK" doctor
run_test "vopk sys-info" bash "$VOPK" sys-info
run_test "vopk kernel" bash "$VOPK" kernel
run_test "vopk disk" bash "$VOPK" disk
run_test "vopk mem" bash "$VOPK" mem
run_test "vopk list-backends" bash "$VOPK" list-backends
run_test "vopk list-commands" bash "$VOPK" list-commands
run_test "vopk config" bash "$VOPK" config
run_test "vopk changelog" bash "$VOPK" changelog

# 4. Dry-run operations
run_test "vopk update --dry-run" bash "$VOPK" update --dry-run
run_test "vopk install --dry-run testpkg" bash "$VOPK" install --dry-run testpkg
run_test "vopk remove --dry-run testpkg" bash "$VOPK" remove --dry-run testpkg
run_test "vopk clean --dry-run" bash "$VOPK" clean --dry-run

# 5. Profiles management
run_test "vopk profile list" bash "$VOPK" profile list
run_test "vopk profile create ci-test curl git" bash "$VOPK" profile create ci-test curl git
run_test "vopk profile delete ci-test" bash "$VOPK" profile delete ci-test

# 6. Python compiler & ELF binary
run_test "shell2bin.py compilation" python3 "$SHELL2BIN" "$VOPK" "${SCRIPT_DIR}/bin/vopk_test_bin"
run_test "compiled binary execution" "${SCRIPT_DIR}/bin/vopk_test_bin" --version
rm -f "${SCRIPT_DIR}/bin/vopk_test_bin"

echo "=================================================="
echo " Results: ${PASSED} passed, ${FAILED} failed"
echo "=================================================="

if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi
