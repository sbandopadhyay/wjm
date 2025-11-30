#!/bin/bash
# srun.mod - Immediate job execution (bypasses queue)
# Uses concurrency-safe operations from common.mod
# ALL BUGS FIXED
# Added --name flag support
# Added --timeout, retry, cpu, memory, project, hooks

# Parse arguments for job file and optional --name
# Added --priority flag support
# Added --preset flag support
JOB_FILE=""
JOB_FRIENDLY_NAME=""
CLI_PRIORITY=""  # Priority from command line (overrides file metadata)
CLI_PRESET=""    # Preset from command line (applies defaults)

# v1.0 Features
CLI_TIMEOUT=""
CLI_RETRY=""
CLI_PROJECT=""
CLI_CPU=""
CLI_MEMORY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            if [[ -z "$2" ]]; then
                error_msg "--name flag requires a value"
                exit 1
            fi
            JOB_FRIENDLY_NAME="$2"
            if ! validate_job_name "$JOB_FRIENDLY_NAME"; then
                exit 1
            fi
            shift 2
            ;;
        --priority)
            if [[ -z "$2" ]]; then
                error_msg "--priority flag requires a value (urgent/high/normal/low)"
                exit 1
            fi
            CLI_PRIORITY="$2"
            if ! validate_priority "$CLI_PRIORITY"; then
                exit 1
            fi
            shift 2
            ;;
        --preset)
            if [[ -z "$2" ]]; then
                error_msg "--preset flag requires a value (small/medium/large/gpu/urgent)"
                exit 1
            fi
            CLI_PRESET="$2"
            if ! validate_preset "$CLI_PRESET"; then
                exit 1
            fi
            shift 2
            ;;
        --timeout)
            if [[ -z "$2" ]]; then
                error_msg "--timeout flag requires a value (e.g., 2h, 30m, 1d)"
                exit 1
            fi
            CLI_TIMEOUT="$2"
            if ! validate_timeout "$CLI_TIMEOUT"; then
                exit 1
            fi
            shift 2
            ;;
        --retry)
            if [[ -z "$2" ]]; then
                error_msg "--retry flag requires a value (max retry count)"
                exit 1
            fi
            CLI_RETRY="$2"
            if ! validate_retry "$CLI_RETRY"; then
                exit 1
            fi
            shift 2
            ;;
        --project)
            if [[ -z "$2" ]]; then
                error_msg "--project flag requires a value"
                exit 1
            fi
            CLI_PROJECT="$2"
            if ! validate_project "$CLI_PROJECT"; then
                exit 1
            fi
            shift 2
            ;;
        --cpu)
            if [[ -z "$2" ]]; then
                error_msg "--cpu flag requires a value (e.g., 4, 0-3, 0,2,4)"
                exit 1
            fi
            CLI_CPU="$2"
            if ! validate_cpu_spec "$CLI_CPU"; then
                exit 1
            fi
            shift 2
            ;;
        --memory)
            if [[ -z "$2" ]]; then
                error_msg "--memory flag requires a value (e.g., 8G, 512M, 50%)"
                exit 1
            fi
            CLI_MEMORY="$2"
            if ! validate_memory_spec "$CLI_MEMORY"; then
                exit 1
            fi
            shift 2
            ;;
        *)
            if [[ -z "$JOB_FILE" ]]; then
                JOB_FILE="$1"
            fi
            shift
            ;;
    esac
done

# Apply preset if specified
if [[ -n "$CLI_PRESET" ]]; then
    apply_preset "$CLI_PRESET"
fi

# Validate input
if [[ -z "$JOB_FILE" ]]; then
    error_msg "Please specify a job file (e.g., $SCRIPT_NAME -srun myjob.run)"
    exit 1
fi

if [[ ! -f "$JOB_FILE" ]]; then
    error_msg "Job file '$JOB_FILE' does not exist!"
    exit 1
fi

if [[ ! -r "$JOB_FILE" ]]; then
    error_msg "Job file '$JOB_FILE' is not readable!"
    exit 1
fi

# PARSE JOB METADATA

# Parse metadata from job file (WEIGHT, GPU, PRIORITY, and v1.0 directives)
# Use preset values as defaults if preset was specified
if [[ -n "$CLI_PRESET" ]]; then
    JOB_WEIGHT="${PRESET_WEIGHT:-10}"
    GPU_SPEC="${PRESET_GPU:-N/A}"
    JOB_PRIORITY="${PRESET_PRIORITY:-normal}"
else
    JOB_WEIGHT="${DEFAULT_JOB_WEIGHT:-10}"
    GPU_SPEC="N/A"
    JOB_PRIORITY="${DEFAULT_JOB_PRIORITY:-normal}"
fi

# v1.0 metadata defaults
JOB_TIMEOUT="N/A"
JOB_RETRY_MAX="0"
JOB_RETRY_DELAY="60"
JOB_RETRY_ON="N/A"
JOB_CPU="N/A"
JOB_MEMORY="N/A"
JOB_PROJECT="N/A"
JOB_GROUP="N/A"
JOB_PRE_HOOK="N/A"
JOB_POST_HOOK="N/A"
JOB_ON_FAIL="N/A"
JOB_ON_SUCCESS="N/A"

skip_lines=0

# Continue parsing after shebang, don't break
# Add $ anchor to regex patterns
# Allow spaces in GPU list
while IFS= read -r line; do
    # Check for WEIGHT directive
    if [[ "$line" =~ ^#[[:space:]]*WEIGHT:[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
        JOB_WEIGHT="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # Check for GPU directive (allow spaces in list, also handle 'auto' and 'auto:N')
    elif [[ "$line" =~ ^#[[:space:]]*GPU:[[:space:]]*([0-9,[:space:]]+|auto|auto:[0-9]+|any)[[:space:]]*$ ]]; then
        GPU_SPEC="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # Check for PRIORITY directive
    elif [[ "$line" =~ ^#[[:space:]]*PRIORITY:[[:space:]]*([a-z]+)[[:space:]]*$ ]]; then
        JOB_PRIORITY="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.0: TIMEOUT directive
    elif [[ "$line" =~ ^#[[:space:]]*TIMEOUT:[[:space:]]*([0-9]+[smhd]?)[[:space:]]*$ ]]; then
        JOB_TIMEOUT="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.0: RETRY directive
    elif [[ "$line" =~ ^#[[:space:]]*RETRY:[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
        JOB_RETRY_MAX="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.0: RETRY_DELAY directive
    elif [[ "$line" =~ ^#[[:space:]]*RETRY_DELAY:[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
        JOB_RETRY_DELAY="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.0: RETRY_ON directive (exit codes)
    elif [[ "$line" =~ ^#[[:space:]]*RETRY_ON:[[:space:]]*([0-9,]+)[[:space:]]*$ ]]; then
        JOB_RETRY_ON="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.0: CPU directive
    elif [[ "$line" =~ ^#[[:space:]]*CPU:[[:space:]]*([0-9,-]+)[[:space:]]*$ ]]; then
        JOB_CPU="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.0: CORES directive (alias for CPU count)
    elif [[ "$line" =~ ^#[[:space:]]*CORES:[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
        JOB_CPU="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.0: MEMORY directive
    elif [[ "$line" =~ ^#[[:space:]]*MEMORY:[[:space:]]*([0-9]+[KMGT%]?B?)[[:space:]]*$ ]]; then
        JOB_MEMORY="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.0: PROJECT directive
    elif [[ "$line" =~ ^#[[:space:]]*PROJECT:[[:space:]]*([^[:space:]]+)[[:space:]]*$ ]]; then
        JOB_PROJECT="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.0: GROUP directive
    elif [[ "$line" =~ ^#[[:space:]]*GROUP:[[:space:]]*([^[:space:]]+)[[:space:]]*$ ]]; then
        JOB_GROUP="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.0: PRE_HOOK directive
    elif [[ "$line" =~ ^#[[:space:]]*PRE_HOOK:[[:space:]]*(.+)[[:space:]]*$ ]]; then
        JOB_PRE_HOOK="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.0: POST_HOOK directive
    elif [[ "$line" =~ ^#[[:space:]]*POST_HOOK:[[:space:]]*(.+)[[:space:]]*$ ]]; then
        JOB_POST_HOOK="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.0: ON_FAIL directive
    elif [[ "$line" =~ ^#[[:space:]]*ON_FAIL:[[:space:]]*(.+)[[:space:]]*$ ]]; then
        JOB_ON_FAIL="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.0: ON_SUCCESS directive
    elif [[ "$line" =~ ^#[[:space:]]*ON_SUCCESS:[[:space:]]*(.+)[[:space:]]*$ ]]; then
        JOB_ON_SUCCESS="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # Shebang line - skip it but continue parsing
    elif [[ "$line" =~ ^#! ]]; then
        skip_lines=$((skip_lines + 1))
        continue  # Don't break, keep looking for metadata

    # Empty comment line - skip it
    elif [[ "$line" =~ ^#[[:space:]]*$ ]]; then
        skip_lines=$((skip_lines + 1))

    # Other comment that's not metadata - stop parsing
    elif [[ "$line" =~ ^# ]]; then
        break

    # Non-comment line - stop parsing metadata
    else
        break
    fi
done < "$JOB_FILE"

# v1.0: Override with CLI values if provided
[[ -n "$CLI_PRIORITY" ]] && JOB_PRIORITY="$CLI_PRIORITY"
[[ -n "$CLI_TIMEOUT" ]] && JOB_TIMEOUT="$CLI_TIMEOUT"
[[ -n "$CLI_RETRY" ]] && JOB_RETRY_MAX="$CLI_RETRY"
[[ -n "$CLI_PROJECT" ]] && JOB_PROJECT="$CLI_PROJECT"
[[ -n "$CLI_CPU" ]] && JOB_CPU="$CLI_CPU"
[[ -n "$CLI_MEMORY" ]] && JOB_MEMORY="$CLI_MEMORY"

# v1.0: Handle GPU auto-select
if [[ "$GPU_SPEC" == "auto" ]]; then
    GPU_SPEC=$(auto_select_gpus 1)
    if [[ -z "$GPU_SPEC" ]]; then
        warn_msg "No free GPUs available for auto-select"
        GPU_SPEC="N/A"
    fi
elif [[ "$GPU_SPEC" =~ ^auto:([0-9]+)$ ]]; then
    gpu_count="${BASH_REMATCH[1]}"
    GPU_SPEC=$(auto_select_gpus "$gpu_count")
    if [[ -z "$GPU_SPEC" ]]; then
        warn_msg "Not enough free GPUs for auto-select ($gpu_count requested)"
        GPU_SPEC="N/A"
    fi
fi

# Extract command (skip metadata lines)
if [[ $skip_lines -gt 0 ]]; then
    CMD=$(tail -n +$((skip_lines + 1)) "$JOB_FILE")
else
    CMD=$(cat "$JOB_FILE")
fi

if [[ -z "$CMD" ]]; then
    error_msg "The job file '$JOB_FILE' is empty or contains only metadata!"
    exit 1
fi

# VALIDATE METADATA

# Validate weight
# Don't print duplicate error
if ! validate_weight "$JOB_WEIGHT"; then
    exit 1
fi

if ! validate_priority "$JOB_PRIORITY"; then
    exit 1
fi

# Validate and check GPU availability
if [[ "$GPU_SPEC" != "N/A" ]]; then
    if ! validate_gpu_spec "$GPU_SPEC"; then
        exit 1
    fi

    # For srun, warn but don't block if GPU in use
    if ! check_gpu_availability "$GPU_SPEC"; then
        warn_msg "Requested GPU(s) may already be in use!"
        info_msg "Proceeding anyway (use -qrun for automatic queuing)"
    fi
fi

# CHECK JOB COUNT LIMIT

if ! check_job_count_limit; then
    exit 1
fi

# ACQUIRE JOB ID (ATOMIC)

JOB_NAME=$(acquire_job_id)
if [[ -z "$JOB_NAME" ]]; then
    error_msg "Failed to acquire job ID. System may be overloaded."
    exit 1
fi

JOB_PATH="$JOB_DIR/$JOB_NAME"

# CREATE JOB METADATA

CURRENT_USER=$(get_current_user)

cat > "$JOB_PATH/job.info" <<EOF
JOB_ID=$JOB_NAME
JOB_NAME=$JOB_FRIENDLY_NAME
JOB_FILE=$(basename "$JOB_FILE")
USER=$CURRENT_USER
SUBMIT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
QUEUE_TIME=N/A
START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
STATUS=RUNNING
WEIGHT=$JOB_WEIGHT
GPU=$GPU_SPEC
PRIORITY=$JOB_PRIORITY
TIMEOUT=$JOB_TIMEOUT
RETRY_MAX=$JOB_RETRY_MAX
RETRY_DELAY=$JOB_RETRY_DELAY
RETRY_ON=$JOB_RETRY_ON
RETRY_COUNT=0
CPU=$JOB_CPU
MEMORY=$JOB_MEMORY
PROJECT=$JOB_PROJECT
GROUP=$JOB_GROUP
PRE_HOOK=$JOB_PRE_HOOK
POST_HOOK=$JOB_POST_HOOK
ON_FAIL=$JOB_ON_FAIL
ON_SUCCESS=$JOB_ON_SUCCESS
EOF

# Store command for reference
# Use printf instead of echo
printf '%s\n' "$CMD" > "$JOB_PATH/command.run"

# START JOB

# Generate log file name
# Use parameter expansion
JOB_INDEX="${JOB_NAME#job_}"
LOG_FILE="${LOG_FILE_NAME/XXX/$JOB_INDEX}"

# Create wrapper script that will execute the job
# This approach completely eliminates command injection
# v1.0: Enhanced with timeout, CPU affinity, memory limits, and hooks
cat > "$JOB_PATH/.wrapper.sh" <<'WRAPPER_END'
#!/bin/bash
# Auto-generated job wrapper script (v1.0)

# Read parameters from arguments
JOB_PATH_VAR="$1"
GPU_SPEC_VAR="$2"
TIMEOUT_VAR="$3"
CPU_VAR="$4"
MEMORY_VAR="$5"
PRE_HOOK_VAR="$6"
POST_HOOK_VAR="$7"
ON_FAIL_VAR="$8"
ON_SUCCESS_VAR="$9"
RETRY_MAX_VAR="${10}"
RETRY_DELAY_VAR="${11}"
RETRY_ON_VAR="${12}"

# Helper: Update job.info field
update_info() {
    local field="$1"
    local value="$2"
    grep -v "^${field}=" job.info > job.info.tmp 2>/dev/null
    echo "${field}=${value}" >> job.info.tmp
    mv job.info.tmp job.info
}

# Helper: Parse duration to seconds
parse_duration() {
    local dur="$1"
    local num="${dur%[smhd]}"
    local unit="${dur##*[0-9]}"
    case "$unit" in
        s|'') echo "$num" ;;
        m) echo $((num * 60)) ;;
        h) echo $((num * 3600)) ;;
        d) echo $((num * 86400)) ;;
        *) echo "$num" ;;
    esac
}

# Set CUDA_VISIBLE_DEVICES if GPU specified
if [[ "$GPU_SPEC_VAR" != "N/A" ]]; then
    export CUDA_VISIBLE_DEVICES="$GPU_SPEC_VAR"
fi

# Change to job directory
cd "$JOB_PATH_VAR" || exit 1

# v1.0: Execute pre-hook if specified
if [[ "$PRE_HOOK_VAR" != "N/A" && -n "$PRE_HOOK_VAR" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing pre-hook: $PRE_HOOK_VAR"
    eval "$PRE_HOOK_VAR"
    PRE_HOOK_EXIT=$?
    if [[ $PRE_HOOK_EXIT -ne 0 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pre-hook failed with exit code $PRE_HOOK_EXIT"
        echo $PRE_HOOK_EXIT > exit.code
        echo "END_TIME=$(date '+%Y-%m-%d %H:%M:%S')" >> job.info
        update_info "STATUS" "FAILED"
        update_info "FAIL_REASON" "pre_hook_failed"
        rm -f job.pid
        exit $PRE_HOOK_EXIT
    fi
fi

# Build the execution command
EXEC_CMD="bash command.run"

# v1.0: Apply CPU affinity if specified
if [[ "$CPU_VAR" != "N/A" && -n "$CPU_VAR" ]]; then
    if command -v taskset >/dev/null 2>&1; then
        # Check if it's a count (just a number) or a CPU list
        if [[ "$CPU_VAR" =~ ^[0-9]+$ ]]; then
            # It's a count - generate CPU list 0-(n-1)
            cpu_list="0-$((CPU_VAR - 1))"
            EXEC_CMD="taskset -c $cpu_list $EXEC_CMD"
        else
            # It's a CPU list or range
            EXEC_CMD="taskset -c $CPU_VAR $EXEC_CMD"
        fi
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] CPU affinity set to: $CPU_VAR"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Warning: taskset not available, CPU affinity ignored"
    fi
fi

# v1.0: Apply memory limit if specified
if [[ "$MEMORY_VAR" != "N/A" && -n "$MEMORY_VAR" ]]; then
    # Parse memory spec
    mem_num="${MEMORY_VAR%[KMGT%]*}"
    mem_unit="${MEMORY_VAR##*[0-9]}"

    if [[ "$mem_unit" == "%" ]]; then
        # Percentage of total memory
        total_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
        if [[ -n "$total_kb" ]]; then
            limit_kb=$((total_kb * mem_num / 100))
        fi
    else
        # Absolute value - convert to KB
        case "$mem_unit" in
            K|KB) limit_kb=$mem_num ;;
            M|MB) limit_kb=$((mem_num * 1024)) ;;
            G|GB) limit_kb=$((mem_num * 1024 * 1024)) ;;
            T|TB) limit_kb=$((mem_num * 1024 * 1024 * 1024)) ;;
            *) limit_kb=$((mem_num / 1024)) ;;  # Assume bytes
        esac
    fi

    if [[ -n "$limit_kb" && "$limit_kb" -gt 0 ]]; then
        ulimit -v "$limit_kb" 2>/dev/null
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Memory limit set to: ${limit_kb}KB"
    fi
fi

# v1.0: Apply timeout if specified
TIMEOUT_SECONDS=""
if [[ "$TIMEOUT_VAR" != "N/A" && -n "$TIMEOUT_VAR" ]]; then
    TIMEOUT_SECONDS=$(parse_duration "$TIMEOUT_VAR")
    if command -v timeout >/dev/null 2>&1; then
        EXEC_CMD="timeout --signal=TERM --kill-after=10 ${TIMEOUT_SECONDS}s $EXEC_CMD"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Timeout set to: ${TIMEOUT_SECONDS}s"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Warning: timeout command not available"
    fi
fi

# v1.0: Retry loop
RETRY_COUNT=0
MAX_RETRIES="${RETRY_MAX_VAR:-0}"
RETRY_DELAY="${RETRY_DELAY_VAR:-60}"

while true; do
    # Execute the command
    eval "$EXEC_CMD"
    EXIT_CODE=$?

    # Check for timeout (exit code 124 or 137)
    if [[ $EXIT_CODE -eq 124 || $EXIT_CODE -eq 137 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Job timed out after ${TIMEOUT_SECONDS}s"
        update_info "FAIL_REASON" "timeout"
    fi

    # Check if we should retry
    SHOULD_RETRY=0
    if [[ $EXIT_CODE -ne 0 && "$MAX_RETRIES" -gt 0 && "$RETRY_COUNT" -lt "$MAX_RETRIES" ]]; then
        if [[ "$RETRY_ON_VAR" == "N/A" || -z "$RETRY_ON_VAR" ]]; then
            # Retry on any failure
            SHOULD_RETRY=1
        else
            # Check if exit code matches retry conditions
            IFS=',' read -ra RETRY_CODES <<< "$RETRY_ON_VAR"
            for code in "${RETRY_CODES[@]}"; do
                if [[ "$EXIT_CODE" -eq "$code" ]]; then
                    SHOULD_RETRY=1
                    break
                fi
            done
        fi
    fi

    if [[ $SHOULD_RETRY -eq 1 ]]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        update_info "RETRY_COUNT" "$RETRY_COUNT"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Retry $RETRY_COUNT/$MAX_RETRIES (exit code: $EXIT_CODE, delay: ${RETRY_DELAY}s)"
        sleep "$RETRY_DELAY"
        continue
    fi

    break
done

# Record exit code
echo $EXIT_CODE > exit.code

# Record end time
echo "END_TIME=$(date '+%Y-%m-%d %H:%M:%S')" >> job.info

# Update status (Mac compatible - avoid sed -i)
if [[ $EXIT_CODE -eq 0 ]]; then
    update_info "STATUS" "COMPLETED"

    # v1.0: Execute on-success hook
    if [[ "$ON_SUCCESS_VAR" != "N/A" && -n "$ON_SUCCESS_VAR" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing on-success hook: $ON_SUCCESS_VAR"
        eval "$ON_SUCCESS_VAR"
    fi
else
    update_info "STATUS" "FAILED"

    # v1.0: Execute on-fail hook
    if [[ "$ON_FAIL_VAR" != "N/A" && -n "$ON_FAIL_VAR" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing on-fail hook: $ON_FAIL_VAR"
        eval "$ON_FAIL_VAR"
    fi
fi

# v1.0: Execute post-hook if specified (runs regardless of exit code)
if [[ "$POST_HOOK_VAR" != "N/A" && -n "$POST_HOOK_VAR" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing post-hook: $POST_HOOK_VAR"
    eval "$POST_HOOK_VAR"
fi

# Remove PID file
rm -f job.pid

# Cleanup wrapper script
rm -f .wrapper.sh

exit $EXIT_CODE
WRAPPER_END

# Make wrapper executable
chmod +x "$JOB_PATH/.wrapper.sh"

# Run the wrapper script with all parameters
# v1.0: Added timeout, CPU, memory, hooks, and retry parameters
nohup "$JOB_PATH/.wrapper.sh" \
    "$JOB_PATH" \
    "$GPU_SPEC" \
    "$JOB_TIMEOUT" \
    "$JOB_CPU" \
    "$JOB_MEMORY" \
    "$JOB_PRE_HOOK" \
    "$JOB_POST_HOOK" \
    "$JOB_ON_FAIL" \
    "$JOB_ON_SUCCESS" \
    "$JOB_RETRY_MAX" \
    "$JOB_RETRY_DELAY" \
    "$JOB_RETRY_ON" \
    > "$JOB_PATH/$LOG_FILE" 2>&1 &
PID=$!

# Record PID
echo "$PID" > "$JOB_PATH/job.pid"

# Register PID for orphaned process cleanup
register_pid "$PID" "$JOB_NAME"

# OUTPUT SUCCESS MESSAGE

echo "Job '$JOB_NAME' started immediately (PID: $PID, Weight: $JOB_WEIGHT, GPU: $GPU_SPEC)"
echo "User: $CURRENT_USER"
echo "Log file: $JOB_PATH/$LOG_FILE"
echo "Check status: $SCRIPT_NAME -status"

# Log action (thread-safe)
log_action_safe "User $CURRENT_USER started immediate job $JOB_NAME (Weight: $JOB_WEIGHT, GPU: $GPU_SPEC)"
