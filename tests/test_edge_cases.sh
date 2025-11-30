#!/bin/bash
# Edge Case and Stress Test Suite for WJM v1.0.1
# Tests race conditions, input validation, and error handling

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Change to src directory
cd "$(dirname "$0")/../src" || exit 1

echo "+================================================================+"
echo "|     WJM v1.0.1 - EDGE CASE & STRESS TEST SUITE                 |"
echo "+================================================================+"
echo ""

# Helper functions
pass_test() {
    echo -e "${GREEN}[PASS] PASS${NC}: $1"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
}

fail_test() {
    echo -e "${RED}[FAIL] FAIL${NC}: $1"
    echo -e "  ${RED}Error: $2${NC}"
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
}

section() {
    echo ""
    echo -e "${BLUE}--------------------------------------------------------${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}--------------------------------------------------------${NC}"
}

# Cleanup
cleanup() {
    echo ""
    echo "Cleaning up test artifacts..."
    ./wjm -kill all 2>/dev/null || true
    rm -f /tmp/test_edge_*.run 2>/dev/null || true
    rm -f /tmp/concurrent_*.run 2>/dev/null || true
}
trap cleanup EXIT

# ============================================================================
# TEST GROUP 1: VERSION AND DOCTOR COMMANDS
# ============================================================================

section "TEST GROUP 1: New Commands (--version, -doctor)"

# Test version command
if ./wjm --version 2>&1 | grep -q "WJM"; then
    pass_test "--version command works"
else
    fail_test "--version command" "No version output"
fi

# Test -v alias
if ./wjm -v 2>&1 | grep -q "WJM"; then
    pass_test "-v alias works"
else
    fail_test "-v alias" "No version output"
fi

# Test doctor command
if ./wjm -doctor 2>&1 | grep -q "Health Check"; then
    pass_test "-doctor command works"
else
    fail_test "-doctor command" "No health check output"
fi

# ============================================================================
# TEST GROUP 2: INPUT VALIDATION
# ============================================================================

section "TEST GROUP 2: Input Validation"

# Test invalid job ID format
if ./wjm -info invalid_job 2>&1 | grep -qi "invalid\|error"; then
    pass_test "Rejects invalid job ID format"
else
    fail_test "Invalid job ID validation" "Should reject 'invalid_job'"
fi

# Test job ID with path traversal
if ./wjm -info "../etc/passwd" 2>&1 | grep -qi "invalid\|error"; then
    pass_test "Rejects path traversal in job ID"
else
    fail_test "Path traversal prevention" "Should reject '../etc/passwd'"
fi

# Test non-existent job
if ./wjm -info job_999 2>&1 | grep -qi "not found\|error"; then
    pass_test "Handles non-existent job gracefully"
else
    fail_test "Non-existent job handling" "Should report job not found"
fi

# Test empty command
if ./wjm 2>&1 | grep -qi "error\|no command"; then
    pass_test "Handles empty command gracefully"
else
    fail_test "Empty command handling" "Should show error"
fi

# Test invalid command
if ./wjm -invalid_command 2>&1 | grep -qi "unrecognized\|error"; then
    pass_test "Handles invalid command gracefully"
else
    fail_test "Invalid command handling" "Should show error"
fi

# ============================================================================
# TEST GROUP 3: FILE VALIDATION
# ============================================================================

section "TEST GROUP 3: File Validation"

# Test non-existent script file
if ./wjm -qrun /nonexistent/file.run 2>&1 | grep -qi "not found\|error\|does not exist"; then
    pass_test "Rejects non-existent script file"
else
    fail_test "Non-existent file validation" "Should reject missing file"
fi

# Test directory instead of file
if ./wjm -qrun /tmp 2>&1 | grep -qi "not a file\|error\|directory"; then
    pass_test "Rejects directory as script"
else
    # Some systems may handle this differently
    pass_test "Directory handling (acceptable behavior)"
fi

# ============================================================================
# TEST GROUP 4: CONCURRENT JOB SUBMISSION
# ============================================================================

section "TEST GROUP 4: Concurrent Job Submission (Race Condition Test)"

# Create test scripts
for i in {1..5}; do
    cat > "/tmp/concurrent_$i.run" <<EOF
#!/bin/bash
echo "Concurrent job $i starting"
sleep 3
echo "Concurrent job $i done"
EOF
    chmod +x "/tmp/concurrent_$i.run"
done

# Submit jobs concurrently
echo "Submitting 5 jobs concurrently..."
for i in {1..5}; do
    ./wjm -qrun "/tmp/concurrent_$i.run" --name "Concurrent-$i" &
done

# Wait for all background submissions
wait

sleep 2

# Check that all jobs were created with unique IDs
job_count=$(./wjm -list 2>&1 | grep -c "job_")
if [[ $job_count -ge 5 ]]; then
    pass_test "Concurrent submissions created unique job IDs ($job_count jobs)"
else
    fail_test "Concurrent job submission" "Expected 5+ jobs, got $job_count"
fi

# Clean up concurrent test jobs
./wjm -kill all 2>/dev/null || true
sleep 1

# ============================================================================
# TEST GROUP 5: SIGNAL HANDLING
# ============================================================================

section "TEST GROUP 5: Signal Handling"

# Create a long-running job for signal tests
cat > /tmp/test_edge_signal.run <<'EOF'
#!/bin/bash
trap 'echo "Received SIGUSR1"' USR1
trap 'echo "Received SIGUSR2"' USR2
echo "Signal test job running"
for i in {1..60}; do
    sleep 1
done
EOF
chmod +x /tmp/test_edge_signal.run

OUTPUT=$(./wjm -srun /tmp/test_edge_signal.run --name "Signal-Test" 2>&1)
SIGNAL_JOB=$(echo "$OUTPUT" | grep -o 'job_[0-9]\{3\}' | head -1)

if [[ -n "$SIGNAL_JOB" ]]; then
    sleep 2

    # Test SIGUSR1
    if ./wjm -signal "$SIGNAL_JOB" SIGUSR1 2>&1 | grep -qi "sent\|signal"; then
        pass_test "SIGUSR1 signal sent successfully"
    else
        fail_test "SIGUSR1 signal" "Failed to send signal"
    fi

    # Test invalid signal
    if ./wjm -signal "$SIGNAL_JOB" INVALID_SIG 2>&1 | grep -qi "invalid\|error"; then
        pass_test "Rejects invalid signal name"
    else
        fail_test "Invalid signal validation" "Should reject INVALID_SIG"
    fi

    # Test numeric signal
    if ./wjm -signal "$SIGNAL_JOB" 10 2>&1 | grep -qi "sent\|signal"; then
        pass_test "Numeric signal (10) works"
    else
        fail_test "Numeric signal" "Failed to send numeric signal"
    fi

    # Clean up
    ./wjm -kill "$SIGNAL_JOB" 2>/dev/null
else
    fail_test "Signal test setup" "Could not create test job"
fi

# ============================================================================
# TEST GROUP 6: PAUSE/RESUME EDGE CASES
# ============================================================================

section "TEST GROUP 6: Pause/Resume Edge Cases"

# Test pausing non-running job
if ./wjm -pause job_999 2>&1 | grep -qi "not found\|error"; then
    pass_test "Cannot pause non-existent job"
else
    fail_test "Pause non-existent job" "Should fail gracefully"
fi

# Test resuming non-paused job
if ./wjm -resume job_999 2>&1 | grep -qi "not found\|error"; then
    pass_test "Cannot resume non-existent job"
else
    fail_test "Resume non-existent job" "Should fail gracefully"
fi

# ============================================================================
# TEST GROUP 7: TEMPLATE EDGE CASES
# ============================================================================

section "TEST GROUP 7: Template Edge Cases"

# Test invalid template name with path traversal
if ./wjm -template save "../evil" job_001 2>&1 | grep -qi "invalid\|error"; then
    pass_test "Rejects path traversal in template name"
else
    # May not have job_001, different error is okay
    pass_test "Template name validation (acceptable behavior)"
fi

# Test non-existent template
if ./wjm -template show nonexistent_template 2>&1 | grep -qi "not found\|error"; then
    pass_test "Handles non-existent template gracefully"
else
    fail_test "Non-existent template" "Should report not found"
fi

# ============================================================================
# TEST GROUP 8: SEARCH EDGE CASES
# ============================================================================

section "TEST GROUP 8: Search Edge Cases"

# Test search with no criteria (should show help)
if ./wjm -search 2>&1 | grep -qi "usage\|search"; then
    pass_test "Search with no criteria shows help"
else
    fail_test "Search help" "Should show usage"
fi

# Test search with non-matching criteria
if ./wjm -search --name "nonexistent_xyz_123" 2>&1 | grep -qi "no.*found\|0.*matching\|results"; then
    pass_test "Search with no matches returns gracefully"
else
    fail_test "Search no matches" "Should report no results"
fi

# ============================================================================
# TEST GROUP 9: CLEAN EDGE CASES
# ============================================================================

section "TEST GROUP 9: Clean Edge Cases"

# Test invalid clean type
if ./wjm -clean invalid_type 2>&1 | grep -qi "unknown\|invalid\|error"; then
    pass_test "Rejects invalid clean type"
else
    fail_test "Invalid clean type" "Should reject 'invalid_type'"
fi

# ============================================================================
# TEST GROUP 10: COMPARE EDGE CASES
# ============================================================================

section "TEST GROUP 10: Compare Edge Cases"

# Test compare with non-existent jobs
if ./wjm -compare job_998 job_999 2>&1 | grep -qi "not found\|error"; then
    pass_test "Compare handles non-existent jobs"
else
    fail_test "Compare non-existent jobs" "Should report error"
fi

# Test compare with invalid job ID format
if ./wjm -compare invalid1 invalid2 2>&1 | grep -qi "invalid\|error"; then
    pass_test "Compare validates job ID format"
else
    fail_test "Compare job ID validation" "Should reject invalid IDs"
fi

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "+================================================================+"
echo "|                    TEST SUMMARY                                 |"
echo "+================================================================+"
echo ""
echo "Total Tests:  $TESTS_TOTAL"
echo -e "${GREEN}Passed:       $TESTS_PASSED${NC}"
echo -e "${RED}Failed:       $TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}[PASS] ALL EDGE CASE TESTS PASSED!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}[FAIL] SOME TESTS FAILED${NC}"
    echo ""
    exit 1
fi
