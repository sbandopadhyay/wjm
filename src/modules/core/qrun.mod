#!/bin/bash
# qrun.mod - Queued job execution (respects resource limits)
# Uses concurrency-safe operations from common.mod
# ALL BUGS FIXED - Version 3.0
# Added --name flag support
# VERSION 1.1: Added timeout, retry, cpu, memory, project, array, queue, hooks

# Parse arguments for job file, optional --name, and internal flags
# Added --priority flag support
# Added --preset flag support
# Added --depends-on flag support
JOB_FILE=""
JOB_FRIENDLY_NAME=""
CLI_PRIORITY=""
CLI_PRESET=""
CLI_DEPENDS=""
FROM_QUEUE=""
QUEUE_JOB_WEIGHT=""

# v1.1 Features
CLI_TIMEOUT=""
CLI_RETRY=""
CLI_PROJECT=""
CLI_QUEUE=""
CLI_ARRAY=""
CLI_CPU=""
CLI_MEMORY=""

# Check if called from queue processor (old-style positional args)
if [[ "$2" == "from_queue" ]]; then
    JOB_FILE="$1"
    FROM_QUEUE="$2"
    QUEUE_JOB_WEIGHT="$3"
else
    # Parse command-line arguments
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
            --depends-on)
                if [[ -z "$2" ]]; then
                    error_msg "--depends-on flag requires a value (comma-separated job IDs)"
                    exit 1
                fi
                CLI_DEPENDS="$2"
                if ! validate_dependencies "$CLI_DEPENDS"; then
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
            --queue)
                if [[ -z "$2" ]]; then
                    error_msg "--queue flag requires a value"
                    exit 1
                fi
                CLI_QUEUE="$2"
                if ! validate_queue "$CLI_QUEUE"; then
                    exit 1
                fi
                shift 2
                ;;
            --array)
                if [[ -z "$2" ]]; then
                    error_msg "--array flag requires a value (e.g., 1-100, 1-100:10)"
                    exit 1
                fi
                CLI_ARRAY="$2"
                if ! validate_array_spec "$CLI_ARRAY"; then
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
fi

# HANDLE JOB ARRAYS

if [[ -n "$CLI_ARRAY" && "$FROM_QUEUE" != "from_queue" ]]; then
    ARRAY_ID="array_$(date +%s)_$$"
    ARRAY_INDICES=$(parse_array_spec "$CLI_ARRAY")
    ARRAY_COUNT=$(echo "$ARRAY_INDICES" | wc -w)

    echo "Submitting job array: $ARRAY_COUNT jobs"
    echo "Array ID: $ARRAY_ID"
    echo ""

    ARRAY_JOB_IDS=()
    for idx in $ARRAY_INDICES; do
        # Create wrapper script for this array element
        TEMP_SCRIPT=$(mktemp /tmp/wjm_array_XXXXXX.run)

        # Add array environment variables to script
        cat > "$TEMP_SCRIPT" <<ARRAY_HEADER
#!/bin/bash
export WJM_ARRAY_INDEX=$idx
export WJM_ARRAY_ID=$ARRAY_ID
export WJM_ARRAY_SIZE=$ARRAY_COUNT

ARRAY_HEADER
        cat "$JOB_FILE" >> "$TEMP_SCRIPT"
        chmod +x "$TEMP_SCRIPT"

        # Build submission args (without --array)
        ARRAY_ARGS=("$TEMP_SCRIPT")
        [[ -n "$JOB_FRIENDLY_NAME" ]] && ARRAY_ARGS+=("--name" "${JOB_FRIENDLY_NAME}[$idx]")
        [[ -n "$CLI_PRIORITY" ]] && ARRAY_ARGS+=("--priority" "$CLI_PRIORITY")
        [[ -n "$CLI_TIMEOUT" ]] && ARRAY_ARGS+=("--timeout" "$CLI_TIMEOUT")
        [[ -n "$CLI_PROJECT" ]] && ARRAY_ARGS+=("--project" "$CLI_PROJECT")
        [[ -n "$CLI_CPU" ]] && ARRAY_ARGS+=("--cpu" "$CLI_CPU")
        [[ -n "$CLI_MEMORY" ]] && ARRAY_ARGS+=("--memory" "$CLI_MEMORY")

        # Submit array element
        OUTPUT=$(source "$MODULES_DIR/core/qrun.mod" "${ARRAY_ARGS[@]}" 2>&1)
        JOB_ID=$(echo "$OUTPUT" | grep -o "job_[0-9]\{3\}" | head -1)

        if [[ -n "$JOB_ID" ]]; then
            ARRAY_JOB_IDS+=("$JOB_ID")
            echo "  [$idx] $JOB_ID"

            # Store array metadata in job
            if [[ -f "$JOB_DIR/$JOB_ID/job.info" ]]; then
                echo "ARRAY_ID=$ARRAY_ID" >> "$JOB_DIR/$JOB_ID/job.info"
                echo "ARRAY_INDEX=$idx" >> "$JOB_DIR/$JOB_ID/job.info"
            fi
        fi

        rm -f "$TEMP_SCRIPT"
    done

    echo ""
    echo "Submitted $ARRAY_COUNT array jobs"
    echo "Job IDs: ${ARRAY_JOB_IDS[*]}"
    exit 0
fi

# Validate input
if [[ -z "$JOB_FILE" ]]; then
    error_msg "Please specify a job file (e.g., $SCRIPT_NAME -qrun myjob.run)"
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

# Parse metadata from job file (WEIGHT, GPU, PRIORITY, and v1.1 directives)
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

# v1.1 metadata defaults
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

    # v1.1: TIMEOUT directive
    elif [[ "$line" =~ ^#[[:space:]]*TIMEOUT:[[:space:]]*([0-9]+[smhd]?)[[:space:]]*$ ]]; then
        JOB_TIMEOUT="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.1: RETRY directive
    elif [[ "$line" =~ ^#[[:space:]]*RETRY:[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
        JOB_RETRY_MAX="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.1: RETRY_DELAY directive
    elif [[ "$line" =~ ^#[[:space:]]*RETRY_DELAY:[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
        JOB_RETRY_DELAY="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.1: RETRY_ON directive (exit codes)
    elif [[ "$line" =~ ^#[[:space:]]*RETRY_ON:[[:space:]]*([0-9,]+)[[:space:]]*$ ]]; then
        JOB_RETRY_ON="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.1: CPU directive
    elif [[ "$line" =~ ^#[[:space:]]*CPU:[[:space:]]*([0-9,-]+)[[:space:]]*$ ]]; then
        JOB_CPU="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.1: CORES directive (alias for CPU count)
    elif [[ "$line" =~ ^#[[:space:]]*CORES:[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
        JOB_CPU="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.1: MEMORY directive
    elif [[ "$line" =~ ^#[[:space:]]*MEMORY:[[:space:]]*([0-9]+[KMGT%]?B?)[[:space:]]*$ ]]; then
        JOB_MEMORY="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.1: PROJECT directive
    elif [[ "$line" =~ ^#[[:space:]]*PROJECT:[[:space:]]*([^[:space:]]+)[[:space:]]*$ ]]; then
        JOB_PROJECT="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.1: GROUP directive
    elif [[ "$line" =~ ^#[[:space:]]*GROUP:[[:space:]]*([^[:space:]]+)[[:space:]]*$ ]]; then
        JOB_GROUP="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.1: PRE_HOOK directive
    elif [[ "$line" =~ ^#[[:space:]]*PRE_HOOK:[[:space:]]*(.+)[[:space:]]*$ ]]; then
        JOB_PRE_HOOK="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.1: POST_HOOK directive
    elif [[ "$line" =~ ^#[[:space:]]*POST_HOOK:[[:space:]]*(.+)[[:space:]]*$ ]]; then
        JOB_POST_HOOK="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.1: ON_FAIL directive
    elif [[ "$line" =~ ^#[[:space:]]*ON_FAIL:[[:space:]]*(.+)[[:space:]]*$ ]]; then
        JOB_ON_FAIL="${BASH_REMATCH[1]}"
        skip_lines=$((skip_lines + 1))

    # v1.1: ON_SUCCESS directive
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

# Override with queue weight if provided
[[ -n "$QUEUE_JOB_WEIGHT" ]] && JOB_WEIGHT="$QUEUE_JOB_WEIGHT"

# Override with CLI priority if provided
[[ -n "$CLI_PRIORITY" ]] && JOB_PRIORITY="$CLI_PRIORITY"

# v1.1: Override with CLI values if provided
[[ -n "$CLI_TIMEOUT" ]] && JOB_TIMEOUT="$CLI_TIMEOUT"
[[ -n "$CLI_RETRY" ]] && JOB_RETRY_MAX="$CLI_RETRY"
[[ -n "$CLI_PROJECT" ]] && JOB_PROJECT="$CLI_PROJECT"
[[ -n "$CLI_CPU" ]] && JOB_CPU="$CLI_CPU"
[[ -n "$CLI_MEMORY" ]] && JOB_MEMORY="$CLI_MEMORY"

# v1.1: Handle GPU auto-select
if [[ "$GPU_SPEC" == "auto" ]]; then
    GPU_SPEC=$(auto_select_gpus 1)
    if [[ -z "$GPU_SPEC" ]]; then
        info_msg "No free GPUs available for auto-select, job will be queued"
        GPU_SPEC="auto"  # Keep as auto for queue, will be resolved when started
    fi
elif [[ "$GPU_SPEC" =~ ^auto:([0-9]+)$ ]]; then
    gpu_count="${BASH_REMATCH[1]}"
    GPU_SPEC=$(auto_select_gpus "$gpu_count")
    if [[ -z "$GPU_SPEC" ]]; then
        info_msg "Not enough free GPUs for auto-select ($gpu_count requested), job will be queued"
        GPU_SPEC="auto:$gpu_count"  # Keep for queue
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

# Validate priority
if ! validate_priority "$JOB_PRIORITY"; then
    exit 1
fi

# Validate and check GPU availability
if [[ "$GPU_SPEC" != "N/A" ]]; then
    if ! validate_gpu_spec "$GPU_SPEC"; then
        exit 1
    fi
fi

# CHECK RESOURCE LIMITS (DECIDE WHETHER TO QUEUE OR START)

# RACE CONDITION FIX: Acquire global lock to prevent multiple qrun processes
# from simultaneously checking resources and all deciding to start jobs
# Use mkdir-based locking (simple, atomic, portable)
# Only acquire lock if not coming from queue processor (avoids deadlock)
QRUN_LOCK="$JOB_DIR/.qrun_critical.lock"
if [[ "$FROM_QUEUE" != "from_queue" ]]; then
    lock_acquired=0
    lock_timeout=30
    lock_elapsed=0

    while [[ $lock_elapsed -lt $lock_timeout ]]; do
        if mkdir "$QRUN_LOCK" 2>/dev/null; then
            lock_acquired=1
            break
        fi
        sleep 0.1
        lock_elapsed=$((lock_elapsed + 1))
    done

    if [[ $lock_acquired -eq 0 ]]; then
        error_msg "Failed to acquire qrun lock after ${lock_timeout}s"
        exit 1
    fi

    # Ensure lock is released on exit
    trap 'rmdir "$QRUN_LOCK" 2>/dev/null' EXIT INT TERM
fi

# Calculate current resource usage (thread-safe)
read running_jobs total_weight <<< "$(calculate_resource_usage)"

# Check if we should queue this job
should_queue=0
queue_reason=""  # Track why job is queued

if [[ "$FROM_QUEUE" != "from_queue" ]]; then
    # Check concurrent job limit
    if [[ "$MAX_CONCURRENT_JOBS" -gt 0 && "$running_jobs" -ge "$MAX_CONCURRENT_JOBS" ]]; then
        should_queue=1
        queue_reason="Job limit reached ($running_jobs/$MAX_CONCURRENT_JOBS jobs)"
        info_msg "$queue_reason"
    fi

    # Check weight limit
    if [[ "$MAX_TOTAL_WEIGHT" -gt 0 ]]; then
        new_total=$((total_weight + JOB_WEIGHT))
        if [[ "$new_total" -gt "$MAX_TOTAL_WEIGHT" ]]; then
            should_queue=1
            queue_reason="Would exceed weight limit ($total_weight + $JOB_WEIGHT = $new_total/$MAX_TOTAL_WEIGHT)"
            info_msg "$queue_reason"
        fi
    fi

    # Check GPU availability (if GPU requested)
    if [[ "$GPU_SPEC" != "N/A" ]]; then
        if ! check_gpu_availability "$GPU_SPEC"; then
            should_queue=1
            allocated_gpus=$(get_allocated_gpus)
            queue_reason="Requested GPU(s) $GPU_SPEC in use (allocated: $allocated_gpus)"
            info_msg "$queue_reason"
        fi
    fi
fi

# CHECK JOB COUNT LIMIT

if ! check_job_count_limit; then
    exit 1
fi

# QUEUE JOB IF LIMITS REACHED

if [[ "$should_queue" -eq 1 ]]; then
    # Acquire atomic job ID for queue file
    JOB_NAME=$(acquire_job_id)
    if [[ -z "$JOB_NAME" ]]; then
        error_msg "Failed to acquire job ID for queuing. System may be overloaded."
        exit 1
    fi

    # Extract index from job name
    JOB_INDEX="${JOB_NAME#job_}"
    QUEUED_FILE="$QUEUE_DIR/${JOB_NAME}.run"

    # Copy job file to queue
    cp "$JOB_FILE" "$QUEUED_FILE"

    # Store weight in queue metadata
    echo "$JOB_WEIGHT" > "$QUEUE_DIR/${JOB_NAME}.weight"

    # Store GPU spec in queue metadata
    echo "$GPU_SPEC" > "$QUEUE_DIR/${JOB_NAME}.gpu"

    # Store priority in queue metadata
    echo "$JOB_PRIORITY" > "$QUEUE_DIR/${JOB_NAME}.priority"

    # Store dependencies if specified
    if [[ -n "$CLI_DEPENDS" ]]; then
        echo "$CLI_DEPENDS" > "$QUEUE_DIR/${JOB_NAME}.depends"
    fi

    # Store submit time for accurate queue duration tracking
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$QUEUE_DIR/${JOB_NAME}.submit_time"

    # Store job friendly name if provided
    if [[ -n "$JOB_FRIENDLY_NAME" ]]; then
        echo "$JOB_FRIENDLY_NAME" > "$QUEUE_DIR/${JOB_NAME}.name"
    fi

    # Store queue reason
    if [[ -n "$queue_reason" ]]; then
        echo "$queue_reason" > "$QUEUE_DIR/${JOB_NAME}.reason"
    fi

    # Remove the job directory (we only need it in queue)
    rmdir "$JOB_DIR/$JOB_NAME" 2>/dev/null

    echo "Job queued as '$JOB_NAME' (Running: $running_jobs/$MAX_CONCURRENT_JOBS, Weight: $total_weight+$JOB_WEIGHT/$MAX_TOTAL_WEIGHT, GPU: $GPU_SPEC)"
    if [[ -n "$queue_reason" ]]; then
        echo "   Reason: $queue_reason"
    fi
    echo "Check queue: $SCRIPT_NAME -list"

    # Log action (thread-safe)
    CURRENT_USER=$(get_current_user)
    log_action_safe "User $CURRENT_USER queued job $JOB_NAME (Weight: $JOB_WEIGHT, GPU: $GPU_SPEC)"

    # RACE CONDITION FIX: Release qrun lock before exiting (trap will also do this)
    rmdir "$QRUN_LOCK" 2>/dev/null

    exit 0
fi

# START JOB IMMEDIATELY (RESOURCE LIMITS OK)

# Acquire atomic job ID
JOB_NAME=$(acquire_job_id)
if [[ -z "$JOB_NAME" ]]; then
    error_msg "Failed to acquire job ID. System may be overloaded."
    exit 1
fi

JOB_PATH="$JOB_DIR/$JOB_NAME"

# CREATE JOB METADATA

CURRENT_USER=$(get_current_user)

# Preserve original submit time and name for queued jobs
SUBMIT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
QUEUE_TIME="N/A"

if [[ "$FROM_QUEUE" == "from_queue" ]]; then
    # Job was queued - read original submit time
    if [[ -f "$QUEUE_DIR/${JOB_NAME}.submit_time" ]]; then
        SUBMIT_TIME=$(cat "$QUEUE_DIR/${JOB_NAME}.submit_time" 2>/dev/null)
        QUEUE_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    fi

    # Read friendly name if it was saved
    if [[ -f "$QUEUE_DIR/${JOB_NAME}.name" ]]; then
        JOB_FRIENDLY_NAME=$(cat "$QUEUE_DIR/${JOB_NAME}.name" 2>/dev/null)
    fi
fi

cat > "$JOB_PATH/job.info" <<EOF
JOB_ID=$JOB_NAME
JOB_NAME=$JOB_FRIENDLY_NAME
JOB_FILE=$(basename "$JOB_FILE")
USER=$CURRENT_USER
SUBMIT_TIME=$SUBMIT_TIME
QUEUE_TIME=$QUEUE_TIME
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
# v1.1: Enhanced with timeout, CPU affinity, memory limits, and hooks
cat > "$JOB_PATH/.wrapper.sh" <<'WRAPPER_END'
#!/bin/bash
# Auto-generated job wrapper script (v1.1)

# Read parameters from arguments
JOB_PATH_VAR="$1"
GPU_SPEC_VAR="$2"
MODULES_DIR_VAR="$3"
TIMEOUT_VAR="$4"
CPU_VAR="$5"
MEMORY_VAR="$6"
PRE_HOOK_VAR="$7"
POST_HOOK_VAR="$8"
ON_FAIL_VAR="$9"
ON_SUCCESS_VAR="${10}"
RETRY_MAX_VAR="${11}"
RETRY_DELAY_VAR="${12}"
RETRY_ON_VAR="${13}"

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

# v1.1: Execute pre-hook if specified
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

# v1.1: Apply CPU affinity if specified
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

# v1.1: Apply memory limit if specified
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

# v1.1: Apply timeout if specified
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

# v1.1: Retry loop
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

    # v1.1: Execute on-success hook
    if [[ "$ON_SUCCESS_VAR" != "N/A" && -n "$ON_SUCCESS_VAR" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing on-success hook: $ON_SUCCESS_VAR"
        eval "$ON_SUCCESS_VAR"
    fi
else
    update_info "STATUS" "FAILED"

    # v1.1: Execute on-fail hook
    if [[ "$ON_FAIL_VAR" != "N/A" && -n "$ON_FAIL_VAR" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing on-fail hook: $ON_FAIL_VAR"
        eval "$ON_FAIL_VAR"
    fi
fi

# v1.1: Execute post-hook if specified (runs regardless of exit code)
if [[ "$POST_HOOK_VAR" != "N/A" && -n "$POST_HOOK_VAR" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing post-hook: $POST_HOOK_VAR"
    eval "$POST_HOOK_VAR"
fi

# Remove PID file
rm -f job.pid

# Trigger queue processing
# Make synchronous to prevent race conditions
if [[ -f "$MODULES_DIR_VAR/utilities/queue.mod" ]]; then
    source "$MODULES_DIR_VAR/utilities/queue.mod" 2>/dev/null
fi

# Cleanup wrapper script
rm -f .wrapper.sh

exit $EXIT_CODE
WRAPPER_END

# Make wrapper executable
chmod +x "$JOB_PATH/.wrapper.sh"

# Run the wrapper script with all parameters
# v1.1: Added timeout, CPU, memory, hooks, and retry parameters
nohup "$JOB_PATH/.wrapper.sh" \
    "$JOB_PATH" \
    "$GPU_SPEC" \
    "$MODULES_DIR" \
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

# RACE CONDITION FIX: Release qrun lock now that job is started
# (lock is only held if not from queue processor; trap will also do this)
if [[ "$FROM_QUEUE" != "from_queue" ]]; then
    rmdir "$QRUN_LOCK" 2>/dev/null
fi

# OUTPUT SUCCESS MESSAGE

echo "Job '$JOB_NAME' started (PID: $PID, Weight: $JOB_WEIGHT, GPU: $GPU_SPEC)"
echo "User: $CURRENT_USER"
echo "Log file: $JOB_PATH/$LOG_FILE"
echo "Check status: $SCRIPT_NAME -status"

# Log action (thread-safe)
log_action_safe "User $CURRENT_USER started job $JOB_NAME (Weight: $JOB_WEIGHT, GPU: $GPU_SPEC)"
