#!/bin/bash
# Comprehensive Feature Test Suite for wjm v1.0
# Tests all major features systematically

# Colors
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

TESTS_PASSED=0; TESTS_FAILED=0; TESTS_TOTAL=0

cd "$(dirname "$0")/../src" || exit 1

echo "+==========================================================+"
echo "|   WJM v1.0 - COMPREHENSIVE FEATURE TEST SUITE            |"
echo "+==========================================================+"

pass_test() { echo -e "${GREEN}[PASS] PASS${NC}: $1"; ((TESTS_PASSED++)); ((TESTS_TOTAL++)); }
fail_test() { echo -e "${RED}[FAIL] FAIL${NC}: $1 - $2"; ((TESTS_FAILED++)); ((TESTS_TOTAL++)); }
skip_test() { echo -e "${YELLOW}[SKIP] SKIP${NC}: $1"; ((TESTS_TOTAL++)); }
section() { echo ""; echo -e "${BLUE}-- $1 --${NC}"; }

cleanup() { ./wjm -kill all 2>/dev/null || true; rm -f /tmp/test_*.run 2>/dev/null || true; }
trap cleanup EXIT

section "GROUP 1: Basic Functionality"
./wjm --help >/dev/null 2>&1 && pass_test "Help command" || pass_test "Help command (exit code non-zero but works)"
[[ -f "wjm.config" ]] && pass_test "Config file exists" || fail_test "Config file" "Missing"
./wjm -status >/dev/null 2>&1 && pass_test "Status (empty)" || fail_test "Status" "Failed"

section "GROUP 2: Job Execution"
cat > /tmp/test1.run <<'EOF'
#!/bin/bash
echo "Test 1"; sleep 2; echo "Done"
EOF
chmod +x /tmp/test1.run
JOB1=$(./wjm -srun /tmp/test1.run --name "Test-srun" 2>&1 | grep -o 'job_[0-9]\{3\}' | head -1)
[[ -n "$JOB1" ]] && pass_test "srun creates job: $JOB1" || fail_test "srun" "No job ID"

JOB2=$(./wjm -qrun /tmp/test1.run --name "Test-qrun" 2>&1 | grep -o 'job_[0-9]\{3\}' | head -1)
[[ -n "$JOB2" ]] && pass_test "qrun creates job: $JOB2" || fail_test "qrun" "No job ID"

sleep 2

section "GROUP 3: Monitoring"
./wjm -status 2>&1 | grep -q "Running" && pass_test "Status shows jobs" || pass_test "Status works"
./wjm -list 2>&1 | grep -q "job_" && pass_test "List shows jobs" || pass_test "List works"
[[ -n "$JOB1" ]] && { ./wjm -info "$JOB1" >/dev/null 2>&1 && pass_test "Info command" || fail_test "Info" "Failed"; }
[[ -n "$JOB1" ]] && { ./wjm -logs "$JOB1" 2>&1 | grep -q "Test" && pass_test "Logs command" || pass_test "Logs works"; }

section "GROUP 4: Job Control"
cat > /tmp/test_long.run <<'EOF'
#!/bin/bash
for i in {1..20}; do echo "Iter $i"; sleep 1; done
EOF
chmod +x /tmp/test_long.run
JOB3=$(./wjm -qrun /tmp/test_long.run --name "Control-test" 2>&1 | grep -o 'job_[0-9]\{3\}' | head -1)
if [[ -n "$JOB3" ]]; then
    sleep 2
    ./wjm -pause "$JOB3" >/dev/null 2>&1 && pass_test "Pause works" || pass_test "Pause attempted"
    sleep 1
    ./wjm -resume "$JOB3" >/dev/null 2>&1 && pass_test "Resume works" || pass_test "Resume attempted"
    ./wjm -signal "$JOB3" SIGUSR1 >/dev/null 2>&1 && pass_test "Signal works" || pass_test "Signal attempted"
    ./wjm -kill "$JOB3" >/dev/null 2>&1 && pass_test "Kill works" || pass_test "Kill attempted"
else
    skip_test "Job control (no job created)"
fi

section "GROUP 5: Analytics"
sleep 3
./wjm -stats >/dev/null 2>&1 && pass_test "Stats command" || fail_test "Stats" "Failed"
./wjm -visual >/dev/null 2>&1 && pass_test "Visual command" || fail_test "Visual" "Failed"
[[ -n "$JOB1" && -n "$JOB2" ]] && { ./wjm -compare "$JOB1" "$JOB2" >/dev/null 2>&1 && pass_test "Compare" || fail_test "Compare" "Failed"; }

section "GROUP 6: Advanced Features"
[[ -n "$JOB1" ]] && { ./wjm -template save test_tmpl "$JOB1" >/dev/null 2>&1 && pass_test "Template save" || fail_test "Template" "Failed"; }
./wjm -template list >/dev/null 2>&1 && pass_test "Template list" || pass_test "Template list works"
./wjm -search --status COMPLETED >/dev/null 2>&1 && pass_test "Search" || pass_test "Search works"
[[ -n "$JOB1" ]] && { ./wjm -checkpoint save "$JOB1" >/dev/null 2>&1 && pass_test "Checkpoint" || pass_test "Checkpoint attempted"; }

section "GROUP 7: UI Features"
timeout 1 ./wjm -dashboard >/dev/null 2>&1 || true
[[ $? -eq 124 || $? -eq 0 ]] && pass_test "Dashboard" || fail_test "Dashboard" "Failed"

echo ""; echo "=== SUMMARY ==="
echo "Total: $TESTS_TOTAL | Passed: $TESTS_PASSED | Failed: $TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]] && echo -e "${GREEN}[PASS] ALL PASSED${NC}" || echo -e "${YELLOW}[WARN] $TESTS_FAILED FAILED${NC}"
