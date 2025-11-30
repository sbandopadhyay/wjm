#!/bin/bash
# pause.mod - Pause a running job

JOB_ID="$1"

if [[ -z "$JOB_ID" ]]; then
    error_msg "Specify a job ID to pause (e.g., $SCRIPT_NAME -pause job_001)"
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

# Check if job is running
if [[ ! -f "$JOB_PATH/job.pid" ]]; then
    error_msg "Job '$JOB_ID' is not running (no PID file found)"
    exit 1
fi

PID=$(cat "$JOB_PATH/job.pid" 2>/dev/null)

# Validate PID is numeric
if [[ ! "$PID" =~ ^[0-9]+$ ]]; then
    error_msg "Invalid PID in job file: '$PID'"
    exit 1
fi

if [[ -z "$PID" ]] || ! ps -p "$PID" > /dev/null 2>&1; then
    error_msg "Job '$JOB_ID' is not running (PID: $PID not found)"
    exit 1
fi

# Check if already paused
STATUS=$(grep "^STATUS=" "$JOB_PATH/job.info" 2>/dev/null | cut -d= -f2)
if [[ "$STATUS" == "PAUSED" ]]; then
    warn_msg "Job '$JOB_ID' is already paused"
    echo ""
    echo "Resume with: $SCRIPT_NAME -resume $JOB_ID"
    exit 0
fi

# Pause the job (send SIGSTOP to entire process group)
PGID=$(ps -o pgid= -p "$PID" 2>/dev/null | tr -d ' ')
if [[ -n "$PGID" && "$PGID" =~ ^[0-9]+$ ]]; then
    # Pause entire process group
    kill -STOP -"$PGID" 2>/dev/null
else
    # Fallback: pause just the main process
    kill -STOP "$PID" 2>/dev/null
fi

if [[ $? -eq 0 ]]; then
    # Properly check sed exit codes for both Linux and macOS
    # Remove old PAUSE_TIME/RESUME_TIME entries to prevent accumulation
    if sed -i.bak '/^PAUSE_TIME=/d; /^RESUME_TIME=/d; s/^STATUS=.*/STATUS=PAUSED/' "$JOB_PATH/job.info" 2>/dev/null; then
        # Linux sed succeeded
        rm -f "$JOB_PATH/job.info.bak"
    elif sed -i '' '/^PAUSE_TIME=/d; /^RESUME_TIME=/d; s/^STATUS=.*/STATUS=PAUSED/' "$JOB_PATH/job.info" 2>/dev/null; then
        # macOS sed succeeded
        :  # No backup file to clean
    else
        # Both sed versions failed
        error_msg "Failed to update job status file"
        exit 1
    fi

    # Record pause time
    if ! echo "PAUSE_TIME=$(date '+%Y-%m-%d %H:%M:%S')" >> "$JOB_PATH/job.info"; then
        error_msg "Failed to record pause time"
        exit 1
    fi

    echo " Job '$JOB_ID' paused successfully"
    echo ""
    echo "Process ID: $PID"
    [[ -n "$PGID" ]] && echo "Process Group: $PGID"
    echo ""
    echo "Resume with: $SCRIPT_NAME -resume $JOB_ID"

    # Log action
    log_action_safe "Paused job: $JOB_ID (PID: $PID)"
else
    error_msg "Failed to pause job '$JOB_ID'"
    exit 1
fi
