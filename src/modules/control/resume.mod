#!/bin/bash
# resume.mod - Resume a paused job

JOB_ID="$1"

if [[ -z "$JOB_ID" ]]; then
    error_msg "Specify a job ID to resume (e.g., $SCRIPT_NAME -resume job_001)"
    exit 1
fi

# Validate job ID format
if [[ ! "$JOB_ID" =~ ^job_[0-9]{3}$ ]]; then
    error_msg "Invalid job ID format. Expected: job_XXX (e.g., job_001)"
    exit 1
fi

# Check if job exists
JOB_PATH="$JOB_DIR/$JOB_ID"
if [[ ! -d "$JOB_PATH" ]]; then
    error_msg "Job '$JOB_ID' not found"
    exit 1
fi

# Check if job has PID
if [[ ! -f "$JOB_PATH/job.pid" ]]; then
    error_msg "Job '$JOB_ID' has no PID file (not running or paused)"
    exit 1
fi

PID=$(cat "$JOB_PATH/job.pid" 2>/dev/null)

# Validate PID is numeric
if [[ ! "$PID" =~ ^[0-9]+$ ]]; then
    error_msg "Invalid PID in job file: '$PID'"
    exit 1
fi

if [[ -z "$PID" ]] || ! ps -p "$PID" > /dev/null 2>&1; then
    error_msg "Job '$JOB_ID' process not found (PID: $PID)"
    exit 1
fi

# Check if paused
STATUS=$(grep "^STATUS=" "$JOB_PATH/job.info" 2>/dev/null | cut -d= -f2)
if [[ "$STATUS" != "PAUSED" ]]; then
    warn_msg "Job '$JOB_ID' is not paused (status: $STATUS)"
    exit 0
fi

# Resume the job (send SIGCONT to entire process group)
PGID=$(ps -o pgid= -p "$PID" 2>/dev/null | tr -d ' ')
if [[ -n "$PGID" && "$PGID" =~ ^[0-9]+$ ]]; then
    # Resume entire process group
    kill -CONT -"$PGID" 2>/dev/null
else
    # Fallback: resume just the main process
    kill -CONT "$PID" 2>/dev/null
fi

if [[ $? -eq 0 ]]; then
    # Properly check sed exit codes for both Linux and macOS
    # Update status
    if sed -i.bak "s/^STATUS=.*/STATUS=RUNNING/" "$JOB_PATH/job.info" 2>/dev/null; then
        # Linux sed succeeded
        rm -f "$JOB_PATH/job.info.bak"
    elif sed -i '' "s/^STATUS=.*/STATUS=RUNNING/" "$JOB_PATH/job.info" 2>/dev/null; then
        # macOS sed succeeded
        :  # No backup file to clean
    else
        # Both sed versions failed
        error_msg "Failed to update job status file"
        exit 1
    fi

    # Record resume time and calculate pause duration
    PAUSE_TIME=$(grep "^PAUSE_TIME=" "$JOB_PATH/job.info" 2>/dev/null | tail -1 | cut -d= -f2)
    if [[ -n "$PAUSE_TIME" ]]; then
        RESUME_TIME=$(date '+%Y-%m-%d %H:%M:%S')
        if ! echo "RESUME_TIME=$RESUME_TIME" >> "$JOB_PATH/job.info"; then
            error_msg "Failed to record resume time"
            exit 1
        fi

        # Calculate pause duration
        pause_epoch=$(date -d "$PAUSE_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$PAUSE_TIME" +%s 2>/dev/null)
        resume_epoch=$(date -d "$RESUME_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$RESUME_TIME" +%s 2>/dev/null)

        if [[ -n "$pause_epoch" && -n "$resume_epoch" ]]; then
            pause_duration=$((resume_epoch - pause_epoch))
            pause_minutes=$((pause_duration / 60))
            pause_seconds=$((pause_duration % 60))
            echo ""
            echo "Paused for: ${pause_minutes}m ${pause_seconds}s"
        fi
    fi

    echo " Job '$JOB_ID' resumed successfully"
    echo ""
    echo "Process ID: $PID"
    [[ -n "$PGID" ]] && echo "Process Group: $PGID"

    # Log action
    log_action_safe "Resumed job: $JOB_ID (PID: $PID)"
else
    error_msg "Failed to resume job '$JOB_ID'"
    exit 1
fi
