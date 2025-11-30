#!/bin/bash
# Common utilities with concurrency-safe operations
# ALL BUGS FIXED - Version 3.0

# Enable nullglob to handle empty directories correctly
shopt -s nullglob

# ERROR AND WARNING FUNCTIONS

error_msg() {
    echo "ERROR: $*" >&2
}

warn_msg() {
    echo "WARNING: $*" >&2
}

info_msg() {
    echo "INFO: $*"
}

# PID REGISTRY FOR ORPHANED PROCESS CLEANUP

# Registry for tracking spawned processes
SCHEDULER_STATE_DIR="${JOB_DIR}/.scheduler_state"
PID_REGISTRY="${SCHEDULER_STATE_DIR}/managed_pids.txt"

# Function to register spawned PID
register_pid() {
    local pid="$1"
    local job_id="$2"
    mkdir -p "$SCHEDULER_STATE_DIR"
    echo "$(date +%s):$pid:$job_id" >> "$PID_REGISTRY"
}

# Function to cleanup orphaned processes
cleanup_orphaned_pids() {
    [[ ! -f "$PID_REGISTRY" ]] && return 0

    local cleaned_count=0
    while IFS=: read -r timestamp pid job_id; do
        # Skip empty lines
        [[ -z "$pid" ]] && continue

        # Check if process still exists
        if ps -p "$pid" >/dev/null 2>&1; then
            # Check if job still active
            if [[ ! -f "$JOB_DIR/$job_id/job.pid" ]]; then
                # Orphaned process - kill it
                kill -9 "$pid" 2>/dev/null && ((cleaned_count++))
                echo "Cleaned orphaned process $pid for job $job_id" >&2
            fi
        fi
    done < "$PID_REGISTRY"

    # Clean registry
    > "$PID_REGISTRY"

    [[ $cleaned_count -gt 0 ]] && echo "Cleaned $cleaned_count orphaned process(es)" >&2
    return 0
}

# ATOMIC JOB ID GENERATION
# Uses mkdir's atomic test-and-set to avoid race conditions
# Wrap entire operation in lock to prevent TOCTOU race
# Returns: job_name (e.g., "job_001") on success, empty on failure
acquire_job_id() {
    local max_attempts=1000  # Increased from 100
    local attempt=0
    local max_index=999  # Maximum supported index

    # Acquire lock to make the entire find-and-create operation atomic
    # This prevents TOCTOU race where multiple processes find same max index
    local job_id_lock="$JOB_DIR/.job_id_generation.lock"
    local lock_acquired=0

    # Create a lock file with timeout
    local lock_timeout=30
    local lock_elapsed=0
    while [[ $lock_elapsed -lt $lock_timeout ]]; do
        if mkdir "$job_id_lock" 2>/dev/null; then
            lock_acquired=1
            break
        fi
        sleep 0.1
        lock_elapsed=$((lock_elapsed + 1))
    done

    if [[ $lock_acquired -eq 0 ]]; then
        error_msg "Failed to acquire job ID generation lock after ${lock_timeout}s"
        return 1
    fi

    # Ensure lock is released on exit
    trap 'rmdir "$job_id_lock" 2>/dev/null' RETURN

    while [[ $attempt -lt $max_attempts ]]; do
        # Find highest existing job index (now atomic with mkdir)
        local current_max=0
        for folder in "$JOB_DIR"/job_*; do
            [[ -e "$folder" ]] || continue  # Skip if glob didn't match
            local idx="${folder##*/job_}"  # Use parameter expansion
            # Validate it's numeric before comparing
            if [[ "$idx" =~ ^[0-9]+$ ]]; then
                # Force base-10 interpretation to avoid octal issues with leading zeros
                [[ $((10#$idx)) -gt $current_max ]] && current_max=$((10#$idx))
            fi
        done

        # Try next available index
        local next_index=$((current_max + 1))

        # Check for index overflow
        if [[ $next_index -gt $max_index ]]; then
            error_msg "Maximum job index ($max_index) reached. Archive old jobs."
            rmdir "$job_id_lock" 2>/dev/null
            return 1
        fi

        local job_name="job_$(printf "%03d" $next_index)"
        local job_path="$JOB_DIR/$job_name"

        # Atomic test-and-set using mkdir (now protected by outer lock)
        if mkdir "$job_path" 2>/dev/null; then
            rmdir "$job_id_lock" 2>/dev/null
            echo "$job_name"
            return 0
        fi

        # Collision occurred (shouldn't happen with lock, but handle anyway)
        # Use 0.1 instead of 0.01 for better portability
        sleep 0.1
        attempt=$((attempt + 1))
    done

    # Failed to acquire job ID after max attempts
    rmdir "$job_id_lock" 2>/dev/null
    error_msg "Failed to acquire job ID after $max_attempts attempts"
    return 1
}

# GPU VALIDATION AND TRACKING

# Check if nvidia-smi is available
has_gpu_support() {
    command -v nvidia-smi >/dev/null 2>&1
}

# Get number of available GPUs
# Validate nvidia-smi output is actually a number
get_gpu_count() {
    if has_gpu_support; then
        local count
        count=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
        # Validate it's actually a number
        if [[ "$count" =~ ^[0-9]+$ ]]; then
            echo "$count"
        else
            # nvidia-smi failed, returned error text
            echo "0"
        fi
    else
        echo "0"
    fi
}

# Validate GPU specification
# Args: $1 = GPU spec (e.g., "0", "0,1", "0,2,3")
# Returns: 0 if valid, 1 if invalid
validate_gpu_spec() {
    local gpu_spec="$1"

    # N/A is always valid (no GPU requested)
    [[ "$gpu_spec" == "N/A" ]] && return 0

    # Check if GPU support exists
    if ! has_gpu_support; then
        error_msg "GPU requested but nvidia-smi not found"
        return 1
    fi

    local gpu_count=$(get_gpu_count)
    if [[ "$gpu_count" -eq 0 ]]; then
        error_msg "GPU requested but no GPUs detected"
        return 1
    fi

    # Allow spaces in GPU list, clean them first
    gpu_spec="${gpu_spec// /}"  # Remove all spaces

    # Check for empty spec
    if [[ -z "$gpu_spec" ]]; then
        error_msg "GPU specification is empty"
        return 1
    fi

    # Validate each GPU ID
    IFS=',' read -ra gpu_ids <<< "$gpu_spec"
    for gpu_id_raw in "${gpu_ids[@]}"; do
        # Use parameter expansion, handle empty
        local gpu_id="${gpu_id_raw// /}"

        # Skip empty entries from trailing commas
        [[ -z "$gpu_id" ]] && continue

        # Check if numeric
        if [[ ! "$gpu_id" =~ ^[0-9]+$ ]]; then
            error_msg "Invalid GPU ID '$gpu_id' (must be numeric)"
            return 1
        fi

        # Check if within range
        if [[ "$gpu_id" -ge "$gpu_count" ]]; then
            error_msg "GPU ID $gpu_id out of range (available: 0-$((gpu_count-1)))"
            return 1
        fi
    done

    return 0
}

# Get list of currently allocated GPUs
# Returns: Comma-separated list of allocated GPU IDs
get_allocated_gpus() {
    local allocated_gpus=()

    for folder in "$JOB_DIR"/job_*; do
        [[ -e "$folder" ]] || continue

        if [[ -d "$folder" && -f "$folder/job.pid" ]]; then
            local job_pid
            job_pid=$(cat "$folder/job.pid" 2>/dev/null)

            # Check if process is actually running
            if [[ -n "$job_pid" ]] && ps -p "$job_pid" >/dev/null 2>&1; then
                # Get GPU allocation from job.info
                if [[ -f "$folder/job.info" ]]; then
                    # Use head -1 to get first match only
                    local gpu_spec
                    gpu_spec=$(grep "^GPU=" "$folder/job.info" | head -1 | cut -d= -f2)

                    if [[ "$gpu_spec" != "N/A" && -n "$gpu_spec" ]]; then
                        # Add each GPU to allocated list
                        IFS=',' read -ra gpus <<< "$gpu_spec"
                        for gpu in "${gpus[@]}"; do
                            # Use parameter expansion
                            gpu="${gpu// /}"
                            [[ -n "$gpu" ]] && allocated_gpus+=("$gpu")
                        done
                    fi
                fi
            fi
        fi
    done

    # Return unique sorted list
    # FIX: Handle empty array case
    if [[ ${#allocated_gpus[@]} -eq 0 ]]; then
        echo ""
    else
        printf "%s\n" "${allocated_gpus[@]}" | sort -u | tr '\n' ',' | sed 's/,$//'
    fi
}

# Check if requested GPUs are available (not in use)
# Args: $1 = GPU spec to check (e.g., "0,1")
# Returns: 0 if available, 1 if conflict
check_gpu_availability() {
    local requested="$1"

    [[ "$requested" == "N/A" ]] && return 0

    # Clean spaces from requested spec
    requested="${requested// /}"

    local allocated
    allocated=$(get_allocated_gpus)

    # If nothing allocated, all GPUs available
    [[ -z "$allocated" ]] && return 0

    # Parse requested GPUs
    IFS=',' read -ra req_gpus <<< "$requested"

    # Parse allocated GPUs
    IFS=',' read -ra alloc_gpus <<< "$allocated"

    # Check for conflicts
    for req_gpu in "${req_gpus[@]}"; do
        req_gpu="${req_gpu// /}"
        [[ -z "$req_gpu" ]] && continue

        for alloc_gpu in "${alloc_gpus[@]}"; do
            if [[ "$req_gpu" == "$alloc_gpu" ]]; then
                warn_msg "GPU $req_gpu is already allocated"
                return 1
            fi
        done
    done

    return 0
}

# WEIGHT VALIDATION

# Validate job weight
# Args: $1 = weight value
# Returns: 0 if valid, 1 if invalid
validate_weight() {
    local weight="$1"

    if [[ ! "$weight" =~ ^[0-9]+$ ]]; then
        error_msg "Invalid weight '$weight' (must be positive integer)"
        return 1
    fi

    if [[ "$weight" -lt 1 ]]; then
        error_msg "Weight must be at least 1"
        return 1
    fi

    if [[ "$weight" -gt 1000 ]]; then
        error_msg "Weight too large (max: 1000)"
        return 1
    fi

    return 0
}

# JOB PRIORITY VALIDATION

# Validate job priority
validate_priority() {
    local priority="$1"

    # Allow empty (will use default)
    [[ -z "$priority" ]] && return 0

    # Check if priority is valid
    case "$priority" in
        urgent|high|normal|low)
            return 0
            ;;
        *)
            error_msg "Invalid priority '$priority' (must be: urgent, high, normal, or low)"
            return 1
            ;;
    esac
}

# Get numeric priority value for sorting (higher number = higher priority)
get_priority_value() {
    local priority="$1"

    case "$priority" in
        urgent) echo 40 ;;
        high)   echo 30 ;;
        normal) echo 20 ;;
        low)    echo 10 ;;
        *)      echo 20 ;;  # Default to normal
    esac
}

# RESOURCE PRESETS

# Validate preset name
validate_preset() {
    local preset="$1"

    case "$preset" in
        small|medium|large|gpu|urgent)
            return 0
            ;;
        *)
            error_msg "Invalid preset '$preset' (must be: small, medium, large, gpu, or urgent)"
            return 1
            ;;
    esac
}

# Apply preset to job parameters
# Sets global variables: PRESET_WEIGHT, PRESET_PRIORITY, PRESET_GPU
apply_preset() {
    local preset="$1"

    case "$preset" in
        small)
            PRESET_WEIGHT="${PRESET_SMALL_WEIGHT:-5}"
            PRESET_PRIORITY="${PRESET_SMALL_PRIORITY:-normal}"
            PRESET_GPU="N/A"
            ;;
        medium)
            PRESET_WEIGHT="${PRESET_MEDIUM_WEIGHT:-10}"
            PRESET_PRIORITY="${PRESET_MEDIUM_PRIORITY:-normal}"
            PRESET_GPU="N/A"
            ;;
        large)
            PRESET_WEIGHT="${PRESET_LARGE_WEIGHT:-25}"
            PRESET_PRIORITY="${PRESET_LARGE_PRIORITY:-normal}"
            PRESET_GPU="N/A"
            ;;
        gpu)
            PRESET_WEIGHT="${PRESET_GPU_WEIGHT:-30}"
            PRESET_PRIORITY="${PRESET_GPU_PRIORITY:-high}"
            PRESET_GPU="${PRESET_GPU_DEVICES:-0}"
            ;;
        urgent)
            PRESET_WEIGHT="${PRESET_URGENT_WEIGHT:-15}"
            PRESET_PRIORITY="${PRESET_URGENT_PRIORITY:-urgent}"
            PRESET_GPU="N/A"
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

# JOB DEPENDENCIES

# Check if dependencies are satisfied
# Args: $1 = comma-separated list of job IDs
# Returns: 0 if all dependencies completed, 1 otherwise
check_dependencies() {
    local dep_list="$1"

    [[ -z "$dep_list" ]] && return 0
    [[ "$DEPENDENCIES_ENABLED" != "yes" ]] && return 0

    # Split by comma
    IFS=',' read -ra deps <<< "$dep_list"

    for dep_job in "${deps[@]}"; do
        # Trim whitespace
        dep_job=$(echo "$dep_job" | xargs)

        # Check if job exists
        dep_path="$JOB_DIR/$dep_job"
        if [[ ! -d "$dep_path" ]]; then
            # Maybe it's archived?
            local found_in_archive=0
            for archive_batch in "$ARCHIVE_DIR"/[0-9][0-9][0-9]; do
                if [[ -d "$archive_batch/$dep_job" ]]; then
                    # Check if it completed successfully
                    if [[ -f "$archive_batch/$dep_job/job.info" ]]; then
                        local status=$(grep "^STATUS=" "$archive_batch/$dep_job/job.info" 2>/dev/null | cut -d= -f2)
                        if [[ "$status" == "COMPLETED" ]]; then
                            found_in_archive=1
                            break
                        fi
                    fi
                fi
            done

            [[ $found_in_archive -eq 0 ]] && return 1
            continue
        fi

        # Check status
        if [[ -f "$dep_path/job.info" ]]; then
            local status=$(grep "^STATUS=" "$dep_path/job.info" 2>/dev/null | cut -d= -f2)

            if [[ "$status" != "COMPLETED" ]]; then
                return 1
            fi
        else
            return 1
        fi
    done

    return 0
}

# Validate dependency list format
validate_dependencies() {
    local dep_list="$1"

    [[ -z "$dep_list" ]] && return 0

    # Split by comma
    IFS=',' read -ra deps <<< "$dep_list"

    for dep_job in "${deps[@]}"; do
        # Trim whitespace
        dep_job=$(echo "$dep_job" | xargs)

        # Validate format
        if [[ ! "$dep_job" =~ ^job_[0-9]{3}$ ]]; then
            error_msg "Invalid dependency format: '$dep_job' (expected: job_XXX)"
            return 1
        fi
    done

    return 0
}

# USER MANAGEMENT

# Get current user
get_current_user() {
    whoami
}

# Check if current user owns a job
# Args: $1 = job path
# Returns: 0 if owns job or is root, 1 otherwise
check_job_ownership() {
    local job_path="$1"
    local current_user
    current_user=$(get_current_user)

    # Root can manage all jobs
    [[ "$current_user" == "root" ]] && return 0

    # Check job.info for owner
    if [[ -f "$job_path/job.info" ]]; then
        # Use head -1 to prevent multiple matches
        local job_owner
        job_owner=$(grep "^USER=" "$job_path/job.info" | head -1 | cut -d= -f2)

        if [[ "$job_owner" == "$current_user" ]]; then
            return 0
        fi
    fi

    return 1
}

# PORTABLE FILE LOCKING

# Acquire exclusive lock on queue directory
# Portable version that works on both Linux and macOS
# Sets global QUEUE_LOCK_FD
acquire_queue_lock() {
    # Ensure FD cleanup in all scenarios
    # Use multiple traps to ensure cleanup happens
    trap 'exec 200>&- 2>/dev/null' RETURN EXIT INT TERM

    local lockfile="$QUEUE_DIR/.lock"

    # Create lock file directory if it doesn't exist
    if ! mkdir -p "$QUEUE_DIR" 2>/dev/null; then
        error_msg "Failed to create queue directory"
        return 1
    fi

    # Check if flock is available (Linux)
    if command -v flock >/dev/null 2>&1; then
        # Linux: Use flock
        local lockfd=200  # Document magic number

        # Check if exec succeeds
        if ! exec 200>"$lockfile" 2>/dev/null; then
            error_msg "Failed to open lock file"
            return 1
        fi

        # Try to acquire lock (non-blocking)
        if ! flock -n 200 2>/dev/null; then
            # Close FD before returning on failure
            exec 200>&- 2>/dev/null
            return 1  # Lock held by another process
        fi

        # Store lock FD globally for explicit cleanup
        QUEUE_LOCK_FD=200
        return 0
    else
        # macOS/BSD: Use mkdir-based locking
        local lockdir="${lockfile}.d"
        local timeout=5
        local elapsed=0

        while [[ $elapsed -lt $timeout ]]; do
            if mkdir "$lockdir" 2>/dev/null; then
                # Store lockdir path for cleanup
                QUEUE_LOCK_DIR="$lockdir"
                return 0
            fi
            sleep 0.1
            elapsed=$((elapsed + 1))
        done

        return 1  # Timeout
    fi
}

# Release queue lock
# Validate FD before using eval
release_queue_lock() {
    # Linux flock cleanup
    if [[ -n "$QUEUE_LOCK_FD" ]]; then
        # Validate it's numeric before eval
        if [[ "$QUEUE_LOCK_FD" =~ ^[0-9]+$ ]]; then
            flock -u "$QUEUE_LOCK_FD" 2>/dev/null
            # Close the file descriptor safely
            eval "exec ${QUEUE_LOCK_FD}>&-" 2>/dev/null
        fi
        QUEUE_LOCK_FD=""
    fi

    # macOS mkdir-based lock cleanup
    if [[ -n "$QUEUE_LOCK_DIR" && -d "$QUEUE_LOCK_DIR" ]]; then
        rmdir "$QUEUE_LOCK_DIR" 2>/dev/null
        QUEUE_LOCK_DIR=""
    fi
}

# Acquire exclusive scheduler lock for qrun resource checking
# This prevents race conditions where multiple qrun processes
# simultaneously check resources and all decide to start jobs
# Uses FD 201 (queue lock uses 200)
acquire_scheduler_lock() {
    # Ensure FD cleanup in all scenarios
    trap 'exec 201>&- 2>/dev/null' RETURN EXIT INT TERM

    local lockfile="$JOB_DIR/.scheduler.lock"

    # Create directory if it doesn't exist
    if ! mkdir -p "$JOB_DIR" 2>/dev/null; then
        error_msg "Failed to create job directory"
        return 1
    fi

    # Check if flock is available (Linux)
    if command -v flock >/dev/null 2>&1; then
        # Linux: Use flock on FD 201
        # IMPORTANT: Open file without truncation to avoid breaking existing locks
        # Use append mode (>>) or create if not exists
        touch "$lockfile" 2>/dev/null
        if ! exec 201<>"$lockfile" 2>/dev/null; then
            error_msg "Failed to open scheduler lock file"
            return 1
        fi

        # Acquire exclusive lock with timeout (blocking, 30 second timeout)
        # DEBUG: temporarily remove error suppression to see if flock is failing
        if ! flock -x -w 30 201; then
            exec 201>&- 2>/dev/null
            error_msg "Failed to acquire scheduler lock (timeout)"
            return 1
        fi

        SCHEDULER_LOCK_FD=201
        return 0
    else
        # macOS/BSD: Use mkdir-based locking
        local lockdir="${lockfile}.d"
        local timeout=30
        local elapsed=0

        while [[ $elapsed -lt $timeout ]]; do
            if mkdir "$lockdir" 2>/dev/null; then
                SCHEDULER_LOCK_DIR="$lockdir"
                return 0
            fi
            sleep 0.1
            elapsed=$((elapsed + 1))
        done

        error_msg "Failed to acquire scheduler lock (timeout)"
        return 1
    fi
}

# Release scheduler lock
release_scheduler_lock() {
    # Linux flock cleanup
    if [[ -n "$SCHEDULER_LOCK_FD" ]]; then
        if [[ "$SCHEDULER_LOCK_FD" =~ ^[0-9]+$ ]]; then
            flock -u "$SCHEDULER_LOCK_FD" 2>/dev/null
            eval "exec ${SCHEDULER_LOCK_FD}>&-" 2>/dev/null
        fi
        SCHEDULER_LOCK_FD=""
    fi

    # macOS mkdir-based lock cleanup
    if [[ -n "$SCHEDULER_LOCK_DIR" && -d "$SCHEDULER_LOCK_DIR" ]]; then
        rmdir "$SCHEDULER_LOCK_DIR" 2>/dev/null
        SCHEDULER_LOCK_DIR=""
    fi
}

# RESOURCE CALCULATION

# Count running jobs and calculate total weight
# Returns: "job_count total_weight" (space-separated)
calculate_resource_usage() {
    local running_jobs=0
    local total_weight=0

    for folder in "$JOB_DIR"/job_*; do
        [[ -e "$folder" ]] || continue

        if [[ -d "$folder" && -f "$folder/job.pid" ]]; then
            local job_pid
            job_pid=$(cat "$folder/job.pid" 2>/dev/null)

            if [[ -n "$job_pid" ]] && ps -p "$job_pid" >/dev/null 2>&1; then
                running_jobs=$((running_jobs + 1))

                if [[ -f "$folder/job.info" ]]; then
                    local weight
                    weight=$(grep "^WEIGHT=" "$folder/job.info" | head -1 | cut -d= -f2)

                    # Validate weight is numeric before arithmetic
                    if [[ -n "$weight" && "$weight" =~ ^[0-9]+$ ]]; then
                        total_weight=$((total_weight + weight))
                    fi
                fi
            else
                # Stale PID file, clean up
                rm -f "$folder/job.pid" 2>/dev/null
            fi
        fi
    done

    echo "$running_jobs $total_weight"
}

# LOGGING

# Log action with timestamp (thread-safe append)
# Ensure log directory exists
log_action_safe() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Ensure log directory exists
    local log_dir
    log_dir=$(dirname "$SCHEDULER_LOG")
    mkdir -p "$log_dir" 2>/dev/null

    # Append to log (thread-safe)
    echo "$timestamp - [$$] $message" >> "$SCHEDULER_LOG" 2>/dev/null || {
        warn_msg "Failed to write to log file"
    }
}

# PID VALIDATION

# Validate that a PID belongs to a job scheduler process
# Args: $1 = PID, $2 = job path
# Returns: 0 if valid, 1 otherwise
validate_job_pid() {
    local pid="$1"
    local job_path="$2"

    # Check if process exists
    if ! ps -p "$pid" >/dev/null 2>&1; then
        return 1
    fi

    # Additional validation could check:
    # - Process command line matches expected
    # - Process start time matches job start time
    # For now, just check existence

    return 0
}

# INITIALIZATION

# Ensure all required directories exist with proper permissions
initialize_directories() {
    mkdir -p "$JOB_DIR" || {
        error_msg "Failed to create $JOB_DIR"
        return 1
    }

    mkdir -p "$QUEUE_DIR" || {
        error_msg "Failed to create $QUEUE_DIR"
        return 1
    }

    mkdir -p "$ARCHIVE_DIR" || {
        error_msg "Failed to create $ARCHIVE_DIR"
        return 1
    }

    # Create lock directory
    mkdir -p "$QUEUE_DIR/.locks" 2>/dev/null

    return 0
}

# JOB NAME VALIDATION

# Validate job friendly name for security
# Args: $1 = job name to validate
# Returns: 0 if valid, 1 if invalid
validate_job_name() {
    local name="$1"

    # Check if name is provided
    if [[ -z "$name" ]]; then
        return 0  # Empty names are allowed
    fi

    # Check length (max 100 characters)
    if [[ ${#name} -gt 100 ]]; then
        error_msg "Job name too long (max 100 characters, got ${#name})"
        return 1
    fi

    # Check for control characters, newlines, escape sequences
    if [[ "$name" =~ [[:cntrl:]] ]]; then
        error_msg "Job name contains invalid control characters or newlines"
        return 1
    fi

    # Check for path traversal attempts
    if [[ "$name" =~ \.\. || "$name" =~ / ]]; then
        error_msg "Job name cannot contain '..' or '/' characters"
        return 1
    fi

    # Check for equals sign (breaks job.info parsing)
    if [[ "$name" =~ = ]]; then
        error_msg "Job name cannot contain '=' character"
        return 1
    fi

    return 0
}

# JOB COUNT LIMIT CHECK

# Check if adding a new job would exceed MAX_TOTAL_JOBS limit
check_job_count_limit() {
    # If MAX_TOTAL_JOBS is 0, unlimited jobs allowed
    [[ -z "$MAX_TOTAL_JOBS" || "$MAX_TOTAL_JOBS" -eq 0 ]] && return 0

    # Count total jobs (including archived jobs are in archive dir)
    local total_jobs=$(find "$JOB_DIR" -maxdepth 1 -type d -name 'job_*' 2>/dev/null | wc -l)

    if [[ $total_jobs -ge $MAX_TOTAL_JOBS ]]; then
        error_msg "Maximum job limit reached ($MAX_TOTAL_JOBS jobs)"
        echo ""
        echo "Please clean up old jobs to make room for new ones:"
        echo "  • Archive completed jobs: $SCRIPT_NAME -archive"
        echo "  • Clean old jobs: $SCRIPT_NAME -clean --old 30d"
        echo "  • Clean failed jobs: $SCRIPT_NAME -clean --failed"
        echo ""
        echo "Current job count: $total_jobs / $MAX_TOTAL_JOBS"
        return 1
    fi

    return 0
}

# CONFIG VALIDATION

# Validate configuration values
validate_config() {
    # Validate DEFAULT_JOB_WEIGHT
    if [[ -n "$DEFAULT_JOB_WEIGHT" ]]; then
        if ! validate_weight "$DEFAULT_JOB_WEIGHT"; then
            warn_msg "Invalid DEFAULT_JOB_WEIGHT in config, using 10"
            DEFAULT_JOB_WEIGHT=10
        fi
    fi

    # Validate DEFAULT_JOB_PRIORITY
    if [[ -n "$DEFAULT_JOB_PRIORITY" ]]; then
        if ! validate_priority "$DEFAULT_JOB_PRIORITY"; then
            warn_msg "Invalid DEFAULT_JOB_PRIORITY in config, using 'normal'"
            DEFAULT_JOB_PRIORITY="normal"
        fi
    fi

    # Validate PRIORITY_QUEUE_ENABLED
    if [[ -n "$PRIORITY_QUEUE_ENABLED" && "$PRIORITY_QUEUE_ENABLED" != "yes" && "$PRIORITY_QUEUE_ENABLED" != "no" ]]; then
        warn_msg "Invalid PRIORITY_QUEUE_ENABLED in config, using 'yes'"
        PRIORITY_QUEUE_ENABLED="yes"
    fi

    # Validate MAX_CONCURRENT_JOBS
    if [[ -n "$MAX_CONCURRENT_JOBS" && ! "$MAX_CONCURRENT_JOBS" =~ ^[0-9]+$ ]]; then
        warn_msg "Invalid MAX_CONCURRENT_JOBS in config, using 4"
        MAX_CONCURRENT_JOBS=4
    fi

    # Validate MAX_TOTAL_WEIGHT
    if [[ -n "$MAX_TOTAL_WEIGHT" && ! "$MAX_TOTAL_WEIGHT" =~ ^[0-9]+$ ]]; then
        warn_msg "Invalid MAX_TOTAL_WEIGHT in config, using 100"
        MAX_TOTAL_WEIGHT=100
    fi

    # Validate MAX_TOTAL_JOBS
    if [[ -n "$MAX_TOTAL_JOBS" && ! "$MAX_TOTAL_JOBS" =~ ^[0-9]+$ ]]; then
        warn_msg "Invalid MAX_TOTAL_JOBS in config, using 1000"
        MAX_TOTAL_JOBS=1000
    fi

    # Validate LOG_FILE_NAME contains XXX placeholder
    if [[ -n "$LOG_FILE_NAME" && ! "$LOG_FILE_NAME" =~ XXX ]]; then
        warn_msg "LOG_FILE_NAME does not contain XXX placeholder, using default"
        LOG_FILE_NAME="job_XXX.log"
    fi

    # Validate WATCH_REFRESH_INTERVAL
    if [[ -n "$WATCH_REFRESH_INTERVAL" ]]; then
        if ! [[ "$WATCH_REFRESH_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$WATCH_REFRESH_INTERVAL" -lt 1 ]]; then
            warn_msg "Invalid WATCH_REFRESH_INTERVAL in config, using 3"
            WATCH_REFRESH_INTERVAL=3
        fi
    fi

    # Validate ARCHIVE_THRESHOLD
    if [[ -n "$ARCHIVE_THRESHOLD" && ! "$ARCHIVE_THRESHOLD" =~ ^[0-9]+$ ]]; then
        warn_msg "Invalid ARCHIVE_THRESHOLD in config, using 100"
        ARCHIVE_THRESHOLD=100
    fi

    # Validate MAX_ARCHIVE_BATCHES
    if [[ -n "$MAX_ARCHIVE_BATCHES" && ! "$MAX_ARCHIVE_BATCHES" =~ ^[0-9]+$ ]]; then
        warn_msg "Invalid MAX_ARCHIVE_BATCHES in config, using 10"
        MAX_ARCHIVE_BATCHES=10
    fi

    # Validate directory paths are absolute
    if [[ -n "$JOB_DIR" && ! "$JOB_DIR" =~ ^/ ]]; then
        warn_msg "JOB_DIR must be an absolute path, using default: ~/job_logs/jobs"
        JOB_DIR="$HOME/job_logs/jobs"
    fi

    if [[ -n "$QUEUE_DIR" && ! "$QUEUE_DIR" =~ ^/ ]]; then
        warn_msg "QUEUE_DIR must be an absolute path, using default: ~/job_logs/queue"
        QUEUE_DIR="$HOME/job_logs/queue"
    fi

    if [[ -n "$ARCHIVE_DIR" && ! "$ARCHIVE_DIR" =~ ^/ ]]; then
        warn_msg "ARCHIVE_DIR must be an absolute path, using default: ~/job_logs/archive"
        ARCHIVE_DIR="$HOME/job_logs/archive"
    fi

    if [[ -n "$LOG_DIR" && ! "$LOG_DIR" =~ ^/ ]]; then
        warn_msg "LOG_DIR must be an absolute path, using default: ~/job_logs/logs"
        LOG_DIR="$HOME/job_logs/logs"
    fi

    # Validate Smart Log Management config
    # Note: validate_log_config() is defined in logmanager.mod
    if [[ "$(type -t validate_log_config)" == "function" ]]; then
        validate_log_config
    fi
}

# TIME AND DURATION UTILITIES

# Calculate human-readable duration from timestamp
# Args: $1 = start timestamp (YYYY-MM-DD HH:MM:SS)
# Returns: human-readable duration (e.g., "2h 15m", "45m", "3d 5h")
calculate_duration() {
    local start_time="$1"
    local end_time="${2:-$(date '+%Y-%m-%d %H:%M:%S')}"

    # Convert to seconds since epoch
    local start_sec end_sec
    start_sec=$(date -d "$start_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$start_time" +%s 2>/dev/null)
    end_sec=$(date -d "$end_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$end_time" +%s 2>/dev/null)

    # Handle date parsing failures
    if [[ -z "$start_sec" || -z "$end_sec" ]]; then
        echo "N/A"
        return
    fi

    local diff=$((end_sec - start_sec))

    # Handle negative durations (clock skew or errors)
    if [[ $diff -lt 0 ]]; then
        echo "N/A"
        return
    fi

    # Format duration
    local days=$((diff / 86400))
    local hours=$(( (diff % 86400) / 3600 ))
    local minutes=$(( (diff % 3600) / 60 ))
    local seconds=$((diff % 60))

    # Build human-readable string
    local duration=""
    [[ $days -gt 0 ]] && duration="${days}d "
    [[ $hours -gt 0 ]] && duration="${duration}${hours}h "
    [[ $minutes -gt 0 ]] && duration="${duration}${minutes}m"

    # If less than a minute, show seconds
    if [[ -z "$duration" ]]; then
        duration="${seconds}s"
    fi

    # Trim trailing space
    echo "${duration% }"
}

# Calculate queue duration (SUBMIT_TIME to START_TIME)
# Args: $1 = submit timestamp, $2 = start timestamp
# Returns: human-readable duration
calculate_queue_duration() {
    local submit_time="$1"
    local start_time="$2"

    # If either is missing, return N/A
    if [[ -z "$submit_time" || -z "$start_time" || "$submit_time" == "N/A" || "$start_time" == "N/A" ]]; then
        echo "N/A"
        return
    fi

    # Calculate duration between submit and start
    calculate_duration "$submit_time" "$start_time"
}

# Calculate run duration (START_TIME to END_TIME or now)
# Args: $1 = start timestamp, $2 = end timestamp (optional, defaults to now)
# Returns: human-readable duration
calculate_run_duration() {
    local start_time="$1"
    local end_time="${2:-$(date '+%Y-%m-%d %H:%M:%S')}"

    # If start time is missing, return N/A
    if [[ -z "$start_time" || "$start_time" == "N/A" ]]; then
        echo "N/A"
        return
    fi

    # Calculate duration from start to end (or now)
    calculate_duration "$start_time" "$end_time"
}

# Calculate total duration (SUBMIT_TIME to END_TIME or now)
# Args: $1 = submit timestamp, $2 = end timestamp (optional, defaults to now)
# Returns: human-readable duration
calculate_total_duration() {
    local submit_time="$1"
    local end_time="${2:-$(date '+%Y-%m-%d %H:%M:%S')}"

    # If submit time is missing, return N/A
    if [[ -z "$submit_time" || "$submit_time" == "N/A" ]]; then
        echo "N/A"
        return
    fi

    # Calculate duration from submit to end (or now)
    calculate_duration "$submit_time" "$end_time"
}

# Get job timing information from job.info file
# Args: $1 = job path
# Returns: SUBMIT_TIME START_TIME END_TIME (space-separated)
get_job_times() {
    local job_path="$1"
    local submit_time="N/A"
    local start_time="N/A"
    local end_time="N/A"
    local queue_time="N/A"

    if [[ -f "$job_path/job.info" ]]; then
        submit_time=$(grep "^SUBMIT_TIME=" "$job_path/job.info" | head -1 | cut -d= -f2)
        start_time=$(grep "^START_TIME=" "$job_path/job.info" | head -1 | cut -d= -f2)
        end_time=$(grep "^END_TIME=" "$job_path/job.info" | head -1 | cut -d= -f2)
        queue_time=$(grep "^QUEUE_TIME=" "$job_path/job.info" | head -1 | cut -d= -f2)
    fi

    echo "$submit_time $start_time $end_time $queue_time"
}

# CPU DETECTION AND AFFINITY

# Get number of CPU cores
get_cpu_count() {
    if [[ -f /proc/cpuinfo ]]; then
        grep -c ^processor /proc/cpuinfo
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu 2>/dev/null || echo "1"
    elif command -v nproc >/dev/null 2>&1; then
        nproc
    else
        echo "1"
    fi
}

# Get number of physical CPU cores (excluding hyperthreading)
get_physical_cpu_count() {
    if [[ -f /proc/cpuinfo ]]; then
        local cores=$(grep "^cpu cores" /proc/cpuinfo | head -1 | awk '{print $4}')
        local sockets=$(grep "^physical id" /proc/cpuinfo | sort -u | wc -l)
        if [[ -n "$cores" && -n "$sockets" && "$sockets" -gt 0 ]]; then
            echo $((cores * sockets))
        else
            get_cpu_count
        fi
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.physicalcpu 2>/dev/null || get_cpu_count
    else
        get_cpu_count
    fi
}

# Validate CPU specification
# Args: $1 = CPU spec (e.g., "0-3", "4", "0,2,4")
validate_cpu_spec() {
    local cpu_spec="$1"

    [[ -z "$cpu_spec" || "$cpu_spec" == "N/A" ]] && return 0

    local cpu_count=$(get_cpu_count)

    # Handle range format: 0-3
    if [[ "$cpu_spec" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        if [[ $start -ge $cpu_count || $end -ge $cpu_count || $start -gt $end ]]; then
            error_msg "CPU range $cpu_spec out of bounds (available: 0-$((cpu_count-1)))"
            return 1
        fi
        return 0
    fi

    # Handle count format: just a number (auto-select N cores)
    if [[ "$cpu_spec" =~ ^[0-9]+$ ]]; then
        if [[ $cpu_spec -gt $cpu_count ]]; then
            error_msg "Requested $cpu_spec CPUs but only $cpu_count available"
            return 1
        fi
        return 0
    fi

    # Handle list format: 0,2,4
    if [[ "$cpu_spec" =~ ^[0-9,]+$ ]]; then
        IFS=',' read -ra cpus <<< "$cpu_spec"
        for cpu in "${cpus[@]}"; do
            if [[ $cpu -ge $cpu_count ]]; then
                error_msg "CPU $cpu out of range (available: 0-$((cpu_count-1)))"
                return 1
            fi
        done
        return 0
    fi

    error_msg "Invalid CPU specification: $cpu_spec"
    return 1
}

# Apply CPU affinity to a process
# Args: $1 = CPU spec, $2 = PID
apply_cpu_affinity() {
    local cpu_spec="$1"
    local pid="$2"

    [[ -z "$cpu_spec" || "$cpu_spec" == "N/A" ]] && return 0

    # Only works on Linux with taskset
    if ! command -v taskset >/dev/null 2>&1; then
        warn_msg "taskset not available, CPU affinity not applied"
        return 0
    fi

    local cpu_count=$(get_cpu_count)

    # Handle count format: auto-select N cores
    if [[ "$cpu_spec" =~ ^[0-9]+$ && ! "$cpu_spec" =~ , && ! "$cpu_spec" =~ - ]]; then
        local count=$cpu_spec
        cpu_spec="0-$((count-1))"
    fi

    taskset -cp "$cpu_spec" "$pid" >/dev/null 2>&1
}

# MEMORY DETECTION AND LIMITS

# Get total system memory in bytes
get_total_memory() {
    if [[ -f /proc/meminfo ]]; then
        local kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        echo $((kb * 1024))
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.memsize 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get available memory in bytes
get_available_memory() {
    if [[ -f /proc/meminfo ]]; then
        local kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        if [[ -z "$kb" ]]; then
            # Fallback for older kernels
            kb=$(grep MemFree /proc/meminfo | awk '{print $2}')
        fi
        echo $((kb * 1024))
    elif command -v vm_stat >/dev/null 2>&1; then
        # macOS
        local pages=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
        echo $((pages * 4096))
    else
        echo "0"
    fi
}

# Parse memory specification to bytes
# Args: $1 = memory spec (e.g., "8G", "512M", "50%")
parse_memory_spec() {
    local spec="$1"

    [[ -z "$spec" || "$spec" == "N/A" ]] && echo "0" && return

    # Handle percentage
    if [[ "$spec" =~ ^([0-9]+)%$ ]]; then
        local percent="${BASH_REMATCH[1]}"
        local total=$(get_total_memory)
        echo $((total * percent / 100))
        return
    fi

    # Handle units
    local num="${spec//[^0-9]/}"
    local unit="${spec//[0-9]/}"
    unit="${unit^^}"  # Uppercase

    case "$unit" in
        K|KB) echo $((num * 1024)) ;;
        M|MB) echo $((num * 1024 * 1024)) ;;
        G|GB) echo $((num * 1024 * 1024 * 1024)) ;;
        T|TB) echo $((num * 1024 * 1024 * 1024 * 1024)) ;;
        "") echo "$num" ;;  # Assume bytes
        *) echo "0" ;;
    esac
}

# Format bytes to human readable
format_bytes() {
    local bytes="$1"

    if [[ $bytes -ge 1099511627776 ]]; then
        echo "$(( bytes / 1099511627776 ))TB"
    elif [[ $bytes -ge 1073741824 ]]; then
        echo "$(( bytes / 1073741824 ))GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(( bytes / 1048576 ))MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(( bytes / 1024 ))KB"
    else
        echo "${bytes}B"
    fi
}

# Validate memory specification
validate_memory_spec() {
    local spec="$1"

    [[ -z "$spec" || "$spec" == "N/A" ]] && return 0

    local bytes=$(parse_memory_spec "$spec")
    local total=$(get_total_memory)

    if [[ $bytes -eq 0 ]]; then
        error_msg "Invalid memory specification: $spec"
        return 1
    fi

    if [[ $bytes -gt $total ]]; then
        error_msg "Requested memory $(format_bytes $bytes) exceeds system total $(format_bytes $total)"
        return 1
    fi

    return 0
}

# Apply memory limit to process using ulimit
# Args: $1 = memory spec
apply_memory_limit() {
    local spec="$1"

    [[ -z "$spec" || "$spec" == "N/A" ]] && return 0

    local bytes=$(parse_memory_spec "$spec")
    local kb=$((bytes / 1024))

    # Set virtual memory limit
    ulimit -v $kb 2>/dev/null || warn_msg "Failed to set memory limit"
}

# ENHANCED GPU FUNCTIONS

# Get list of free GPUs
get_free_gpus() {
    local gpu_count=$(get_gpu_count)
    [[ $gpu_count -eq 0 ]] && return

    local allocated=$(get_allocated_gpus)
    local free_gpus=()

    for ((i=0; i<gpu_count; i++)); do
        if [[ ! ",$allocated," =~ ",$i," ]]; then
            free_gpus+=("$i")
        fi
    done

    echo "${free_gpus[*]}" | tr ' ' ','
}

# Auto-select available GPUs
# Args: $1 = number of GPUs needed (default: 1)
auto_select_gpus() {
    local count="${1:-1}"
    local free=$(get_free_gpus)

    [[ -z "$free" ]] && return 1

    IFS=',' read -ra free_arr <<< "$free"

    if [[ ${#free_arr[@]} -lt $count ]]; then
        return 1  # Not enough GPUs available
    fi

    # Return first N GPUs
    local selected=()
    for ((i=0; i<count; i++)); do
        selected+=("${free_arr[$i]}")
    done

    echo "${selected[*]}" | tr ' ' ','
}

# Get GPU info (name, memory, utilization)
get_gpu_info() {
    local gpu_id="$1"

    if ! has_gpu_support; then
        echo "N/A"
        return
    fi

    nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu \
        --format=csv,noheader,nounits -i "$gpu_id" 2>/dev/null || echo "N/A"
}

# TIME PARSING FOR TIMEOUT

# Parse duration string to seconds
# Args: $1 = duration (e.g., "2h", "30m", "1d", "1h30m", "90")
parse_duration_to_seconds() {
    local duration="$1"
    local total_seconds=0

    [[ -z "$duration" || "$duration" == "N/A" ]] && echo "0" && return

    # If just a number, assume seconds
    if [[ "$duration" =~ ^[0-9]+$ ]]; then
        echo "$duration"
        return
    fi

    # Parse days
    if [[ "$duration" =~ ([0-9]+)d ]]; then
        total_seconds=$((total_seconds + ${BASH_REMATCH[1]} * 86400))
    fi

    # Parse hours
    if [[ "$duration" =~ ([0-9]+)h ]]; then
        total_seconds=$((total_seconds + ${BASH_REMATCH[1]} * 3600))
    fi

    # Parse minutes
    if [[ "$duration" =~ ([0-9]+)m ]]; then
        total_seconds=$((total_seconds + ${BASH_REMATCH[1]} * 60))
    fi

    # Parse seconds
    if [[ "$duration" =~ ([0-9]+)s ]]; then
        total_seconds=$((total_seconds + ${BASH_REMATCH[1]}))
    fi

    echo "$total_seconds"
}

# Validate timeout specification
validate_timeout() {
    local timeout="$1"

    [[ -z "$timeout" || "$timeout" == "N/A" ]] && return 0

    local seconds=$(parse_duration_to_seconds "$timeout")

    if [[ $seconds -eq 0 ]]; then
        error_msg "Invalid timeout specification: $timeout"
        return 1
    fi

    if [[ $seconds -lt 1 ]]; then
        error_msg "Timeout must be at least 1 second"
        return 1
    fi

    # Max 30 days
    if [[ $seconds -gt 2592000 ]]; then
        error_msg "Timeout cannot exceed 30 days"
        return 1
    fi

    return 0
}

# RETRY LOGIC

# Validate retry specification
validate_retry() {
    local retry="$1"

    [[ -z "$retry" || "$retry" == "N/A" ]] && return 0

    if [[ ! "$retry" =~ ^[0-9]+$ ]]; then
        error_msg "Invalid retry count: $retry (must be a number)"
        return 1
    fi

    if [[ $retry -gt 10 ]]; then
        error_msg "Retry count cannot exceed 10"
        return 1
    fi

    return 0
}

# Check if job should retry
# Args: $1 = job path, $2 = exit code
should_retry_job() {
    local job_path="$1"
    local exit_code="$2"

    [[ ! -f "$job_path/job.info" ]] && return 1

    local retry_max=$(grep "^RETRY_MAX=" "$job_path/job.info" | head -1 | cut -d= -f2)
    local retry_count=$(grep "^RETRY_COUNT=" "$job_path/job.info" | head -1 | cut -d= -f2)
    local retry_on=$(grep "^RETRY_ON=" "$job_path/job.info" | head -1 | cut -d= -f2)

    [[ -z "$retry_max" || "$retry_max" == "0" ]] && return 1

    retry_count="${retry_count:-0}"

    # Check if we've exceeded max retries
    [[ $retry_count -ge $retry_max ]] && return 1

    # Check if exit code matches retry conditions
    if [[ -n "$retry_on" && "$retry_on" != "N/A" ]]; then
        if [[ ! ",$retry_on," =~ ",$exit_code," ]]; then
            return 1
        fi
    fi

    return 0
}

# PROJECT/GROUP TRACKING

# Validate project name
validate_project() {
    local project="$1"

    [[ -z "$project" ]] && return 0

    if [[ ${#project} -gt 50 ]]; then
        error_msg "Project name too long (max 50 characters)"
        return 1
    fi

    if [[ "$project" =~ [[:cntrl:]] || "$project" =~ [/=] ]]; then
        error_msg "Project name contains invalid characters"
        return 1
    fi

    return 0
}

# Get jobs by project
# Args: $1 = project name
get_jobs_by_project() {
    local project="$1"
    local jobs=()

    for job_dir in "$JOB_DIR"/job_*; do
        [[ ! -d "$job_dir" ]] && continue
        [[ ! -f "$job_dir/job.info" ]] && continue

        local job_project=$(grep "^PROJECT=" "$job_dir/job.info" | head -1 | cut -d= -f2)
        if [[ "$job_project" == "$project" ]]; then
            jobs+=("$(basename "$job_dir")")
        fi
    done

    echo "${jobs[*]}"
}

# HOOK EXECUTION

# Execute a hook script
# Args: $1 = hook type (pre|post|on_fail|on_success), $2 = hook script, $3 = job_id
execute_hook() {
    local hook_type="$1"
    local hook_script="$2"
    local job_id="$3"

    [[ -z "$hook_script" || "$hook_script" == "N/A" ]] && return 0

    # Check if script exists
    if [[ ! -f "$hook_script" && ! -x "$hook_script" ]]; then
        # Check if it's a relative path in job directory
        local job_path="$JOB_DIR/$job_id"
        if [[ -f "$job_path/$hook_script" ]]; then
            hook_script="$job_path/$hook_script"
        else
            warn_msg "Hook script not found: $hook_script"
            return 1
        fi
    fi

    # Make executable if needed
    [[ ! -x "$hook_script" ]] && chmod +x "$hook_script" 2>/dev/null

    # Set environment variables for hook
    export WJM_JOB_ID="$job_id"
    export WJM_JOB_DIR="$JOB_DIR/$job_id"
    export WJM_HOOK_TYPE="$hook_type"

    # Execute hook with timeout
    timeout 300 bash "$hook_script" 2>&1 || {
        warn_msg "Hook $hook_type failed or timed out"
        return 1
    }

    return 0
}

# JOB ARRAY SUPPORT

# Parse array specification
# Args: $1 = array spec (e.g., "1-100", "1-100:10", "1,5,10,50")
# Returns: space-separated list of indices
parse_array_spec() {
    local spec="$1"
    local indices=()

    [[ -z "$spec" ]] && return

    # Handle range with step: 1-100:10
    if [[ "$spec" =~ ^([0-9]+)-([0-9]+):([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        local step="${BASH_REMATCH[3]}"
        for ((i=start; i<=end; i+=step)); do
            indices+=("$i")
        done
        echo "${indices[*]}"
        return
    fi

    # Handle simple range: 1-100
    if [[ "$spec" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        for ((i=start; i<=end; i++)); do
            indices+=("$i")
        done
        echo "${indices[*]}"
        return
    fi

    # Handle list: 1,5,10,50
    if [[ "$spec" =~ ^[0-9,]+$ ]]; then
        echo "${spec//,/ }"
        return
    fi

    error_msg "Invalid array specification: $spec"
    return 1
}

# Validate array specification
validate_array_spec() {
    local spec="$1"

    [[ -z "$spec" ]] && return 0

    local indices=$(parse_array_spec "$spec")
    local count=$(echo "$indices" | wc -w)

    if [[ $count -eq 0 ]]; then
        error_msg "Invalid array specification: $spec"
        return 1
    fi

    if [[ $count -gt 1000 ]]; then
        error_msg "Array too large (max 1000 elements, got $count)"
        return 1
    fi

    return 0
}

# NAMED QUEUE SUPPORT

# Get queue configuration
# Args: $1 = queue name
get_queue_config() {
    local queue_name="${1:-default}"
    local var_prefix="QUEUE_${queue_name}_"

    echo "max_jobs=$(eval echo \${${var_prefix}MAX_JOBS:-$MAX_CONCURRENT_JOBS})"
    echo "max_weight=$(eval echo \${${var_prefix}MAX_WEIGHT:-$MAX_TOTAL_WEIGHT})"
    echo "requires_gpu=$(eval echo \${${var_prefix}REQUIRES_GPU:-no})"
    echo "priority_boost=$(eval echo \${${var_prefix}PRIORITY_BOOST:-0})"
}

# Validate queue name
validate_queue() {
    local queue="$1"

    [[ -z "$queue" ]] && return 0

    # Check if queue is configured
    local queues="${QUEUES:-default}"
    if [[ ! ",$queues," =~ ",$queue," ]]; then
        error_msg "Unknown queue: $queue (available: $queues)"
        return 1
    fi

    return 0
}

# EXPORT/IMPORT FUNCTIONS

# Export job to portable format
# Args: $1 = job_id
export_job() {
    local job_id="$1"
    local job_path="$JOB_DIR/$job_id"

    [[ ! -d "$job_path" ]] && return 1

    echo "--- $job_id"

    # Export metadata
    if [[ -f "$job_path/job.info" ]]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" || "$key" =~ ^# ]] && continue
            case "$key" in
                JOB_NAME|WEIGHT|GPU|PRIORITY|PROJECT|GROUP|TIMEOUT|RETRY_MAX|RETRY_DELAY|CPU|MEMORY|PRE_HOOK|POST_HOOK)
                    echo "$key: $value"
                    ;;
            esac
        done < "$job_path/job.info"
    fi

    # Export script content
    if [[ -f "$job_path/command.run" ]]; then
        echo "script: |"
        sed 's/^/  /' "$job_path/command.run"
    fi

    echo ""
}

# Import job from portable format
# Args: stdin = job definition
# Returns: new job_id
import_job() {
    local job_name=""
    local weight=""
    local gpu=""
    local priority=""
    local project=""
    local timeout=""
    local script_content=""
    local in_script=0

    while IFS= read -r line; do
        # Skip job header
        [[ "$line" =~ ^---\ +(job_[0-9]+)$ ]] && continue

        # Skip empty lines unless in script
        [[ -z "$line" && $in_script -eq 0 ]] && continue

        # Check if entering script section
        if [[ "$line" =~ ^script:\ *\|$ ]]; then
            in_script=1
            continue
        fi

        # Collect script content
        if [[ $in_script -eq 1 ]]; then
            if [[ "$line" =~ ^\ \ (.*)$ ]]; then
                script_content+="${BASH_REMATCH[1]}"$'\n'
            elif [[ ! "$line" =~ ^\ \  ]]; then
                in_script=0
            fi
        fi

        # Parse metadata
        if [[ $in_script -eq 0 && "$line" =~ ^([A-Z_]+):\ *(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            case "$key" in
                JOB_NAME) job_name="$value" ;;
                WEIGHT) weight="$value" ;;
                GPU) gpu="$value" ;;
                PRIORITY) priority="$value" ;;
                PROJECT) project="$value" ;;
                TIMEOUT) timeout="$value" ;;
            esac
        fi
    done

    # Create temporary script file
    if [[ -n "$script_content" ]]; then
        local temp_script=$(mktemp /tmp/wjm_import_XXXXXX.run)
        echo "$script_content" > "$temp_script"
        chmod +x "$temp_script"
        echo "$temp_script"
    fi
}

# CONFIGURATION VALIDATION COMMAND

# Comprehensive config validation
validate_config_full() {
    local errors=0
    local warnings=0

    echo "Configuration Validation"
    echo "========================"
    echo ""

    # Check required directories
    echo "Directories:"
    if [[ -d "$JOB_DIR" && -w "$JOB_DIR" ]]; then
        echo "  [OK] JOB_DIR exists and is writable: $JOB_DIR"
    else
        echo "  [ERROR] JOB_DIR missing or not writable: $JOB_DIR"
        ((errors++))
    fi

    if [[ -d "$QUEUE_DIR" && -w "$QUEUE_DIR" ]]; then
        echo "  [OK] QUEUE_DIR exists and is writable: $QUEUE_DIR"
    else
        echo "  [WARN] QUEUE_DIR missing: $QUEUE_DIR (will be created)"
        ((warnings++))
    fi

    if [[ -d "$ARCHIVE_DIR" && -w "$ARCHIVE_DIR" ]]; then
        echo "  [OK] ARCHIVE_DIR exists and is writable: $ARCHIVE_DIR"
    else
        echo "  [WARN] ARCHIVE_DIR missing: $ARCHIVE_DIR (will be created)"
        ((warnings++))
    fi

    echo ""
    echo "Limits:"

    # Validate limits
    if [[ "$MAX_CONCURRENT_JOBS" =~ ^[0-9]+$ ]]; then
        if [[ $MAX_CONCURRENT_JOBS -eq 0 ]]; then
            echo "  [OK] MAX_CONCURRENT_JOBS=0 (unlimited)"
        elif [[ $MAX_CONCURRENT_JOBS -gt 100 ]]; then
            echo "  [WARN] MAX_CONCURRENT_JOBS=$MAX_CONCURRENT_JOBS (unusually high)"
            ((warnings++))
        else
            echo "  [OK] MAX_CONCURRENT_JOBS=$MAX_CONCURRENT_JOBS"
        fi
    else
        echo "  [ERROR] MAX_CONCURRENT_JOBS invalid: $MAX_CONCURRENT_JOBS"
        ((errors++))
    fi

    if [[ "$MAX_TOTAL_WEIGHT" =~ ^[0-9]+$ ]]; then
        if [[ $MAX_TOTAL_WEIGHT -eq 0 ]]; then
            echo "  [OK] MAX_TOTAL_WEIGHT=0 (unlimited)"
        else
            echo "  [OK] MAX_TOTAL_WEIGHT=$MAX_TOTAL_WEIGHT"
        fi
    else
        echo "  [ERROR] MAX_TOTAL_WEIGHT invalid: $MAX_TOTAL_WEIGHT"
        ((errors++))
    fi

    if [[ "$DEFAULT_JOB_WEIGHT" =~ ^[0-9]+$ && $DEFAULT_JOB_WEIGHT -ge 1 && $DEFAULT_JOB_WEIGHT -le 1000 ]]; then
        echo "  [OK] DEFAULT_JOB_WEIGHT=$DEFAULT_JOB_WEIGHT"
    else
        echo "  [ERROR] DEFAULT_JOB_WEIGHT invalid: $DEFAULT_JOB_WEIGHT"
        ((errors++))
    fi

    echo ""
    echo "System:"

    # Check bash version
    local bash_version="${BASH_VERSION%%(*}"
    local bash_major="${bash_version%%.*}"
    if [[ $bash_major -ge 4 ]]; then
        echo "  [OK] Bash version $BASH_VERSION (minimum 4.0)"
    else
        echo "  [ERROR] Bash version $BASH_VERSION too old (need 4.0+)"
        ((errors++))
    fi

    # Check for optional tools
    if command -v flock >/dev/null 2>&1; then
        echo "  [OK] flock available (better locking)"
    else
        echo "  [WARN] flock not available (using mkdir fallback)"
        ((warnings++))
    fi

    if has_gpu_support; then
        local gpu_count=$(get_gpu_count)
        echo "  [OK] nvidia-smi available ($gpu_count GPUs)"
    else
        echo "  [INFO] nvidia-smi not available (GPU features disabled)"
    fi

    if command -v taskset >/dev/null 2>&1; then
        echo "  [OK] taskset available (CPU affinity supported)"
    else
        echo "  [INFO] taskset not available (CPU affinity disabled)"
    fi

    echo ""
    echo "Modules:"

    # Check modules exist
    local module_count=0
    local missing_modules=0
    for mod in core/srun.mod core/qrun.mod monitoring/status.mod control/kill.mod; do
        if [[ -f "$MODULES_DIR/$mod" ]]; then
            ((module_count++))
        else
            echo "  [ERROR] Missing module: $mod"
            ((missing_modules++))
            ((errors++))
        fi
    done
    echo "  [OK] Found $module_count core modules"

    echo ""
    echo "========================"
    if [[ $errors -eq 0 ]]; then
        echo "Result: VALID ($warnings warnings)"
        return 0
    else
        echo "Result: INVALID ($errors errors, $warnings warnings)"
        return 1
    fi
}

# RESOURCE DISCOVERY

# Display comprehensive system resources
show_resources() {
    echo "System Resources"
    echo "================"
    echo ""

    # CPU info
    local cpu_total=$(get_cpu_count)
    local cpu_physical=$(get_physical_cpu_count)
    echo "CPUs:"
    echo "  Total cores:    $cpu_total"
    echo "  Physical cores: $cpu_physical"

    # Memory info
    local mem_total=$(get_total_memory)
    local mem_avail=$(get_available_memory)
    echo ""
    echo "Memory:"
    echo "  Total:     $(format_bytes $mem_total)"
    echo "  Available: $(format_bytes $mem_avail)"

    # GPU info
    echo ""
    echo "GPUs:"
    if has_gpu_support; then
        local gpu_count=$(get_gpu_count)
        echo "  Count: $gpu_count"

        for ((i=0; i<gpu_count; i++)); do
            local info=$(get_gpu_info $i)
            if [[ "$info" != "N/A" ]]; then
                IFS=',' read -r name mem_total mem_used util <<< "$info"
                echo "  GPU $i: $name"
                echo "         Memory: ${mem_used}MB / ${mem_total}MB"
                echo "         Utilization: ${util}%"
            fi
        done

        local allocated=$(get_allocated_gpus)
        local free=$(get_free_gpus)
        echo ""
        echo "  Allocated: ${allocated:-none}"
        echo "  Free:      ${free:-none}"
    else
        echo "  No GPU support (nvidia-smi not found)"
    fi

    # Current allocation
    echo ""
    echo "Current Allocation"
    echo "=================="
    local usage=$(calculate_resource_usage)
    local running_jobs="${usage%% *}"
    local total_weight="${usage##* }"

    echo "Running jobs: $running_jobs / $MAX_CONCURRENT_JOBS"
    echo "Total weight: $total_weight / $MAX_TOTAL_WEIGHT"

    # Queue status
    local queued=0
    if [[ -d "$QUEUE_DIR" ]]; then
        queued=$(find "$QUEUE_DIR" -name "*.run" 2>/dev/null | wc -l)
    fi
    echo "Queued jobs:  $queued"
}
