#!/bin/bash
# queue.mod - Queue processor (starts queued jobs when resources available)
# Uses concurrency-safe operations from common.mod
# ALL BUGS FIXED - Version 3.0

# PREVENT CONCURRENT QUEUE PROCESSING

# Try to acquire exclusive queue lock
# If another processor already has the lock, exit silently
if ! acquire_queue_lock; then
    # Another queue processor is already running
    exit 0
fi

# Ensure lock is released on exit
trap release_queue_lock EXIT

# CLEAN UP OLD PROCESSED QUEUE FILES

# Remove old processed queue files (older than 1 day)
# Use safer glob-based cleanup with error checking
if [[ -d "$QUEUE_DIR" ]]; then
    cutoff_time=$(($(date +%s) - 86400))  # 24 hours ago
    for processed_file in "$QUEUE_DIR"/*.processed; do
        [[ ! -f "$processed_file" ]] && continue
        # Check file modification time
        if [[ -n "$cutoff_time" ]]; then
            file_mtime=$(stat -c %Y "$processed_file" 2>/dev/null || stat -f %m "$processed_file" 2>/dev/null)
            if [[ -n "$file_mtime" && "$file_mtime" -lt "$cutoff_time" ]]; then
                rm -f "$processed_file" 2>/dev/null
            fi
        fi
    done
fi

# CHECK RESOURCE AVAILABILITY

# Get current resource usage (thread-safe)
read running_jobs total_weight <<< "$(calculate_resource_usage)"

# Check if we can start more jobs
can_start=0

# Check concurrent job limit
if [[ "$MAX_CONCURRENT_JOBS" -eq 0 || "$running_jobs" -lt "$MAX_CONCURRENT_JOBS" ]]; then
    can_start=1
fi

# If we can't start jobs due to concurrent limit, exit
if [[ "$can_start" -eq 0 ]]; then
    exit 0
fi

# PROCESS QUEUE

# Build priority-sorted list of queued jobs
# Collect all queue files with their priorities
declare -a job_list=()

for queued in "$QUEUE_DIR"/*.run; do
    [[ ! -f "$queued" ]] && continue

    # Get priority from metadata (default to normal if not found)
    priority_file="${queued%.run}.priority"
    if [[ -f "$priority_file" ]]; then
        priority=$(cat "$priority_file" 2>/dev/null)
        [[ -z "$priority" ]] && priority="normal"
    else
        priority="normal"
    fi

    # Get numeric priority value for sorting
    priority_value=$(get_priority_value "$priority")

    # Store: "priority_value|full_path"
    job_list+=("${priority_value}|${queued}")
done

# Sort by priority (highest first) and process
# Sort numerically in reverse order (40, 30, 20, 10)
if [[ ${#job_list[@]} -gt 0 ]]; then
    sorted_jobs=$(printf '%s\n' "${job_list[@]}" | sort -t'|' -k1 -n -r)
else
    sorted_jobs=""
fi

# Process jobs in priority order
while IFS='|' read -r priority_value queued; do
    [[ -z "$queued" || ! -f "$queued" ]] && continue

    # Get job weight from metadata
    weight_file="${queued%.run}.weight"
    if [[ -f "$weight_file" ]]; then
        job_weight=$(cat "$weight_file" 2>/dev/null)

        # Validate weight is numeric before arithmetic
        if [[ ! "$job_weight" =~ ^[0-9]+$ ]]; then
            warn_msg "Invalid weight in $weight_file, using default"
            job_weight="${DEFAULT_JOB_WEIGHT:-10}"
        fi
    else
        job_weight="${DEFAULT_JOB_WEIGHT:-10}"
    fi

    # Get GPU spec from metadata
    gpu_file="${queued%.run}.gpu"
    if [[ -f "$gpu_file" ]]; then
        gpu_spec=$(cat "$gpu_file" 2>/dev/null)
        [[ -z "$gpu_spec" ]] && gpu_spec="N/A"
    else
        gpu_spec="N/A"
    fi

    # Check weight limit (if enabled)
    weight_ok=1
    if [[ "$MAX_TOTAL_WEIGHT" -gt 0 ]]; then
        new_total=$((total_weight + job_weight))
        if [[ "$new_total" -gt "$MAX_TOTAL_WEIGHT" ]]; then
            weight_ok=0
        fi
    fi

    # Check GPU availability (if GPU requested)
    gpu_ok=1
    if [[ "$gpu_spec" != "N/A" ]]; then
        if ! check_gpu_availability "$gpu_spec"; then
            gpu_ok=0
        fi
    fi

    # Check dependencies
    depends_ok=1
    depends_file="${queued%.run}.depends"
    if [[ -f "$depends_file" ]]; then
        depends_list=$(cat "$depends_file" 2>/dev/null)
        if [[ -n "$depends_list" ]] && ! check_dependencies "$depends_list"; then
            depends_ok=0
        fi
    fi

    # If weight, GPU, and dependencies are all ok, start this job
    if [[ "$weight_ok" -eq 1 && "$gpu_ok" -eq 1 && "$depends_ok" -eq 1 ]]; then
        # Get job name from file
        job_name=$(basename "$queued" .run)

        info_msg "Starting queued job $job_name from queue (Weight: $job_weight, GPU: $gpu_spec)"

        # Start the job using qrun.mod
        source "$MODULES_DIR/core/qrun.mod" "$queued" "from_queue" "$job_weight"

        # Mark as processed
        mv "$queued" "$queued.processed" 2>/dev/null

        # Clean up metadata files
        [[ -f "$weight_file" ]] && rm -f "$weight_file"
        [[ -f "$gpu_file" ]] && rm -f "$gpu_file"

        # Clean up queue metadata files
        reason_file="${queued%.run}.reason"
        [[ -f "$reason_file" ]] && rm -f "$reason_file"

        submit_time_file="${queued%.run}.submit_time"
        [[ -f "$submit_time_file" ]] && rm -f "$submit_time_file"

        name_file="${queued%.run}.name"
        [[ -f "$name_file" ]] && rm -f "$name_file"

        # Clean up priority file
        priority_file="${queued%.run}.priority"
        [[ -f "$priority_file" ]] && rm -f "$priority_file"

        # Clean up depends file
        depends_file="${queued%.run}.depends"
        [[ -f "$depends_file" ]] && rm -f "$depends_file"

        # Log action (thread-safe)
        log_action_safe "Started queued job: $job_name (Weight: $job_weight, GPU: $gpu_spec)"

        # Recalculate resources after starting job
        read running_jobs total_weight <<< "$(calculate_resource_usage)"

        # Check if we can start more jobs
        if [[ "$MAX_CONCURRENT_JOBS" -gt 0 && "$running_jobs" -ge "$MAX_CONCURRENT_JOBS" ]]; then
            # Hit concurrent limit, stop processing
            exit 0
        fi

        # Continue to next queued job (loop will continue)
    else
        # This job can't be started yet (weight or GPU conflict)
        # Try next job in queue (backfill scheduling)
        continue
    fi
done <<< "$sorted_jobs"

# No more jobs to start or no resources available
exit 0
