#!/bin/bash
# kill.mod - Job termination with ownership checks
# Uses concurrency-safe operations from common.mod
# ALL BUGS FIXED - Version 3.0

if [[ -z "$1" ]]; then
    error_msg "Specify a job ID or 'all' (e.g., $SCRIPT_NAME -kill job_001)"
    exit 1
fi

CURRENT_USER=$(get_current_user)

# KILL ALL JOBS (ONLY USER'S JOBS OR ROOT)

if [[ "$1" == "all" ]]; then
    killed_count=0
    skipped_count=0

    # Kill running jobs
    # Handle empty glob expansion
    for folder in "$JOB_DIR"/job_*; do
        [[ ! -d "$folder" ]] && continue

        if [[ -f "$folder/job.pid" ]]; then
            # Check ownership before killing
            if check_job_ownership "$folder"; then
                JOB_PID=$(cat "$folder/job.pid" 2>/dev/null)
                if [[ -n "$JOB_PID" ]]; then
                    if kill "$JOB_PID" 2>/dev/null; then
                        echo " Stopped $(basename "$folder") (PID: $JOB_PID)"
                        rm -f "$folder/job.pid"
                        killed_count=$((killed_count + 1))

                        # Update job status to KILLED
                        if [[ -f "$folder/job.info" ]]; then
                            grep -v '^STATUS=' "$folder/job.info" > "$folder/job.info.tmp" 2>/dev/null
                            echo 'STATUS=KILLED' >> "$folder/job.info.tmp"
                            echo "END_TIME=$(date '+%Y-%m-%d %H:%M:%S')" >> "$folder/job.info.tmp"
                            mv "$folder/job.info.tmp" "$folder/job.info"
                        fi

                        # Log action (thread-safe)
                        log_action_safe "User $CURRENT_USER killed job $(basename "$folder") (PID: $JOB_PID)"
                    fi
                fi
            else
                # Not owned by current user
                warn_msg "Skipping $(basename "$folder") (owned by another user)"
                skipped_count=$((skipped_count + 1))
            fi
        fi
    done

    # Remove queued jobs
    # Handle empty glob expansion
    for queued in "$QUEUE_DIR"/*.run; do
        [[ ! -f "$queued" ]] && continue

        job_name=$(basename "$queued" .run)

        # For queued jobs, check if corresponding job directory has ownership info
        # If job directory exists, check ownership; otherwise allow removal
        if [[ -d "$JOB_DIR/$job_name" ]]; then
            if check_job_ownership "$JOB_DIR/$job_name"; then
                rm -f "$queued"
                # Also remove metadata files
                rm -f "${queued%.run}.weight" 2>/dev/null
                rm -f "${queued%.run}.gpu" 2>/dev/null
                rm -f "${queued%.run}.name" 2>/dev/null
                rm -f "${queued%.run}.reason" 2>/dev/null
                rm -f "${queued%.run}.submit_time" 2>/dev/null
                echo " Removed queued job $job_name"
                killed_count=$((killed_count + 1))
                log_action_safe "User $CURRENT_USER removed queued job $job_name"
            else
                warn_msg "Skipping queued job $job_name (owned by another user)"
                skipped_count=$((skipped_count + 1))
            fi
        else
            # No ownership info, allow removal (shouldn't happen normally)
            rm -f "$queued"
            rm -f "${queued%.run}.weight" 2>/dev/null
            rm -f "${queued%.run}.gpu" 2>/dev/null
            rm -f "${queued%.run}.name" 2>/dev/null
            rm -f "${queued%.run}.reason" 2>/dev/null
            rm -f "${queued%.run}.submit_time" 2>/dev/null
            echo " Removed queued job $job_name"
            killed_count=$((killed_count + 1))
            log_action_safe "User $CURRENT_USER removed queued job $job_name"
        fi
    done

    if [[ $killed_count -eq 0 ]]; then
        info_msg "No jobs to kill"
    else
        echo "Killed $killed_count job(s)"
        [[ $skipped_count -gt 0 ]] && info_msg "Skipped $skipped_count job(s) owned by other users"
    fi

    exit 0
fi

# KILL SPECIFIC JOB

# Validate job ID format
if [[ ! "$1" =~ ^job_[0-9]{3}$ ]]; then
    error_msg "Invalid job ID format. Expected format: job_XXX (e.g., job_001)"
    exit 1
fi

JOB_PATH="$JOB_DIR/$1"
QUEUE_PATH="$QUEUE_DIR/$1.run"

# Check if it's a running job
if [[ -f "$JOB_PATH/job.pid" ]]; then
    # Check ownership before killing
    if ! check_job_ownership "$JOB_PATH"; then
        error_msg "Permission denied: Job '$1' is owned by another user"
        exit 1
    fi

    JOB_PID=$(cat "$JOB_PATH/job.pid" 2>/dev/null)

    if [[ -z "$JOB_PID" ]]; then
        error_msg "Failed to read PID for job '$1'"
        exit 1
    fi

    if ps -p "$JOB_PID" > /dev/null 2>&1; then
        if kill "$JOB_PID" 2>/dev/null; then
            echo " Stopped job '$1' (PID: $JOB_PID)"
            rm -f "$JOB_PATH/job.pid"

            # Update job status to KILLED
            if [[ -f "$JOB_PATH/job.info" ]]; then
                grep -v '^STATUS=' "$JOB_PATH/job.info" > "$JOB_PATH/job.info.tmp" 2>/dev/null
                echo 'STATUS=KILLED' >> "$JOB_PATH/job.info.tmp"
                echo "END_TIME=$(date '+%Y-%m-%d %H:%M:%S')" >> "$JOB_PATH/job.info.tmp"
                mv "$JOB_PATH/job.info.tmp" "$JOB_PATH/job.info"
            fi

            # Log action (thread-safe)
            log_action_safe "User $CURRENT_USER killed job $1 (PID: $JOB_PID)"
        else
            error_msg "Failed to kill job '$1' (PID: $JOB_PID)"
            exit 1
        fi
    else
        info_msg "Job '$1' already stopped"
        rm -f "$JOB_PATH/job.pid"
    fi

# Check if it's a queued job
elif [[ -f "$QUEUE_PATH" ]]; then
    # Check ownership before removing from queue
    if [[ -d "$JOB_PATH" ]]; then
        if ! check_job_ownership "$JOB_PATH"; then
            error_msg "Permission denied: Queued job '$1' is owned by another user"
            exit 1
        fi
    fi

    rm -f "$QUEUE_PATH"
    # Also remove metadata files
    rm -f "$QUEUE_DIR/$1.weight" 2>/dev/null
    rm -f "$QUEUE_DIR/$1.gpu" 2>/dev/null
    rm -f "$QUEUE_DIR/$1.name" 2>/dev/null
    rm -f "$QUEUE_DIR/$1.reason" 2>/dev/null
    rm -f "$QUEUE_DIR/$1.submit_time" 2>/dev/null

    echo " Removed queued job '$1'"
    log_action_safe "User $CURRENT_USER removed queued job $1"

else
    error_msg "No active or queued job found for '$1'"
    exit 1
fi
