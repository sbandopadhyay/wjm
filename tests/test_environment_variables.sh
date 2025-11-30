#!/bin/bash
# Test suite for environment variable support
# Verifies that WJM properly handles environment variables in job scripts

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

cd "$(dirname "$0")/../src" || exit 1

echo "+================================================================+"
echo "|     WJM - Environment Variable Support Test Suite             |"
echo "+================================================================+"
echo ""

pass_test() {
    echo -e "${GREEN}[PASS] PASS${NC}: $1"
    ((TESTS_PASSED++))
}

fail_test() {
    echo -e "${RED}[FAIL] FAIL${NC}: $1"
    echo -e "  ${RED}Error: $2${NC}"
    ((TESTS_FAILED++))
}

cleanup() {
    echo ""
    echo "Cleaning up test jobs..."
    ./wjm -kill all 2>/dev/null || true
    rm -f /tmp/test_env_*.run 2>/dev/null || true
    rm -f /tmp/env_test_output_*.txt 2>/dev/null || true
}

trap cleanup EXIT

echo "--------------------------------------------------------"
echo "  Test 1: Basic Environment Variables"
echo "--------------------------------------------------------"

# Create test job
cat > /tmp/test_env_basic.run <<'EOF'
#!/bin/bash
export TEST_VAR="hello_world"
export TEST_NUM=12345
echo "TEST_VAR: $TEST_VAR"
echo "TEST_NUM: $TEST_NUM"
echo "$TEST_VAR" > /tmp/env_test_output_basic.txt
exit 0
EOF
chmod +x /tmp/test_env_basic.run

# Submit and wait
OUTPUT=$(./wjm -srun /tmp/test_env_basic.run --name "test-env-basic" 2>&1)
JOB_ID=$(echo "$OUTPUT" | grep -o 'job_[0-9]\{3\}' | head -1)

if [[ -n "$JOB_ID" ]]; then
    sleep 3  # Wait for job to complete

    # Check if output file was created with correct value
    if [[ -f /tmp/env_test_output_basic.txt ]]; then
        CONTENT=$(cat /tmp/env_test_output_basic.txt)
        if [[ "$CONTENT" == "hello_world" ]]; then
            pass_test "Basic environment variables work"
        else
            fail_test "Basic environment variables" "Got '$CONTENT' instead of 'hello_world'"
        fi
    else
        fail_test "Basic environment variables" "Output file not created"
    fi
else
    fail_test "Basic environment variables" "Job submission failed"
fi

echo ""
echo "--------------------------------------------------------"
echo "  Test 2: Sourcing External Files"
echo "--------------------------------------------------------"

# Create external environment file
cat > /tmp/test_external_env.sh <<'EOF'
export EXTERNAL_VAR="from_external_file"
export EXTERNAL_NUM=99999
EOF

# Create test job that sources it
cat > /tmp/test_env_source.run <<'EOF'
#!/bin/bash
source /tmp/test_external_env.sh
echo "EXTERNAL_VAR: $EXTERNAL_VAR"
echo "$EXTERNAL_VAR:$EXTERNAL_NUM" > /tmp/env_test_output_source.txt
exit 0
EOF
chmod +x /tmp/test_env_source.run

# Submit and wait
OUTPUT=$(./wjm -srun /tmp/test_env_source.run --name "test-env-source" 2>&1)
JOB_ID=$(echo "$OUTPUT" | grep -o 'job_[0-9]\{3\}' | head -1)

if [[ -n "$JOB_ID" ]]; then
    sleep 3

    if [[ -f /tmp/env_test_output_source.txt ]]; then
        CONTENT=$(cat /tmp/env_test_output_source.txt)
        if [[ "$CONTENT" == "from_external_file:99999" ]]; then
            pass_test "Sourcing external files works"
        else
            fail_test "Sourcing external files" "Got '$CONTENT' instead of expected value"
        fi
    else
        fail_test "Sourcing external files" "Output file not created"
    fi
else
    fail_test "Sourcing external files" "Job submission failed"
fi

echo ""
echo "--------------------------------------------------------"
echo "  Test 3: PATH Modification"
echo "--------------------------------------------------------"

cat > /tmp/test_env_path.run <<'EOF'
#!/bin/bash
export PATH="/custom/bin:$PATH"
echo "PATH: $PATH"
# Check if /custom/bin is in PATH
if [[ "$PATH" == /custom/bin:* ]]; then
    echo "SUCCESS" > /tmp/env_test_output_path.txt
else
    echo "FAILED" > /tmp/env_test_output_path.txt
fi
exit 0
EOF
chmod +x /tmp/test_env_path.run

OUTPUT=$(./wjm -srun /tmp/test_env_path.run --name "test-env-path" 2>&1)
JOB_ID=$(echo "$OUTPUT" | grep -o 'job_[0-9]\{3\}' | head -1)

if [[ -n "$JOB_ID" ]]; then
    sleep 3

    if [[ -f /tmp/env_test_output_path.txt ]]; then
        CONTENT=$(cat /tmp/env_test_output_path.txt)
        if [[ "$CONTENT" == "SUCCESS" ]]; then
            pass_test "PATH modification works"
        else
            fail_test "PATH modification" "PATH not modified correctly"
        fi
    else
        fail_test "PATH modification" "Output file not created"
    fi
else
    fail_test "PATH modification" "Job submission failed"
fi

echo ""
echo "--------------------------------------------------------"
echo "  Test 4: GPU Environment (CUDA_VISIBLE_DEVICES)"
echo "--------------------------------------------------------"

cat > /tmp/test_env_gpu.run <<'EOF'
# GPU: 0
#!/bin/bash
echo "CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
echo "$CUDA_VISIBLE_DEVICES" > /tmp/env_test_output_gpu.txt
exit 0
EOF
chmod +x /tmp/test_env_gpu.run

OUTPUT=$(./wjm -srun /tmp/test_env_gpu.run --name "test-env-gpu" 2>&1)
JOB_ID=$(echo "$OUTPUT" | grep -o 'job_[0-9]\{3\}' | head -1)

if [[ -n "$JOB_ID" ]]; then
    sleep 3

    if [[ -f /tmp/env_test_output_gpu.txt ]]; then
        CONTENT=$(cat /tmp/env_test_output_gpu.txt)
        if [[ "$CONTENT" == "0" ]]; then
            pass_test "GPU environment variable (CUDA_VISIBLE_DEVICES) auto-set"
        else
            fail_test "GPU environment" "Expected '0', got '$CONTENT'"
        fi
    else
        fail_test "GPU environment" "Output file not created"
    fi
else
    fail_test "GPU environment" "Job submission failed"
fi

echo ""
echo "--------------------------------------------------------"
echo "  Test 5: Multiple Environment Variables"
echo "--------------------------------------------------------"

cat > /tmp/test_env_multiple.run <<'EOF'
#!/bin/bash
export VAR1="value1"
export VAR2="value2"
export VAR3="value3"
export OMP_NUM_THREADS=8
export MKL_NUM_THREADS=4

RESULT="$VAR1:$VAR2:$VAR3:$OMP_NUM_THREADS:$MKL_NUM_THREADS"
echo "$RESULT" > /tmp/env_test_output_multiple.txt
exit 0
EOF
chmod +x /tmp/test_env_multiple.run

OUTPUT=$(./wjm -srun /tmp/test_env_multiple.run --name "test-env-multiple" 2>&1)
JOB_ID=$(echo "$OUTPUT" | grep -o 'job_[0-9]\{3\}' | head -1)

if [[ -n "$JOB_ID" ]]; then
    sleep 3

    if [[ -f /tmp/env_test_output_multiple.txt ]]; then
        CONTENT=$(cat /tmp/env_test_output_multiple.txt)
        if [[ "$CONTENT" == "value1:value2:value3:8:4" ]]; then
            pass_test "Multiple environment variables work"
        else
            fail_test "Multiple environment variables" "Got '$CONTENT'"
        fi
    else
        fail_test "Multiple environment variables" "Output file not created"
    fi
else
    fail_test "Multiple environment variables" "Job submission failed"
fi

echo ""
echo "--------------------------------------------------------"
echo "  Test Summary"
echo "--------------------------------------------------------"

TOTAL=$((TESTS_PASSED + TESTS_FAILED))
echo ""
echo "Tests Passed: $TESTS_PASSED / $TOTAL"
echo "Tests Failed: $TESTS_FAILED / $TOTAL"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}[PASS] All tests passed!${NC}"
    echo ""
    echo "✅ WJM fully supports environment variables"
    exit 0
else
    echo -e "${RED}[FAIL] Some tests failed${NC}"
    exit 1
fi
