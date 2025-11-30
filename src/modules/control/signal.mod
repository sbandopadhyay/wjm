#!/bin/bash
# signal.mod - Send signals to jobs

JOB_ID="$1"
SIGNAL="$2"

if [[ -z "$JOB_ID" || -z "$SIGNAL" ]]; then
    echo "📡 Send Signals to Jobs"
    echo "========================================================"
    echo ""
    echo "Usage: $SCRIPT_NAME -signal <job_id> <signal>"
    echo ""
    echo "Common signals:"
    echo "  SIGTERM (15)  - Graceful termination (default for -kill)"
    echo "  SIGKILL (9)   - Force kill (cannot be caught)"
    echo "  SIGINT (2)    - Interrupt (Ctrl+C)"
    echo "  SIGHUP (1)    - Hangup (reload config)"
    echo "  SIGUSR1 (10)  - User-defined signal 1"
    echo "  SIGUSR2 (12)  - User-defined signal 2"
    echo ""
    echo "Examples:"
    echo "  $SCRIPT_NAME -signal job_001 SIGTERM"
    echo "  $SCRIPT_NAME -signal job_001 SIGUSR1"
    echo "  $SCRIPT_NAME -signal job_001 15"
    echo ""
    echo "Note: Use -pause/-resume for SIGSTOP/SIGCONT"
    exit 0
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

# Normalize signal name
SIGNAL=$(echo "$SIGNAL" | tr '[:lower:]' '[:upper:]')

# If signal is numeric, leave as-is; otherwise add SIG prefix if needed
if [[ ! "$SIGNAL" =~ ^[0-9]+$ ]]; then
    if [[ ! "$SIGNAL" =~ ^SIG ]]; then
        SIGNAL="SIG$SIGNAL"
    fi
fi

# Validate signal
if ! kill -l "$SIGNAL" &>/dev/null; then
    error_msg "Invalid signal: $SIGNAL"
    echo ""
    echo "Valid signals: SIGTERM, SIGKILL, SIGINT, SIGHUP, SIGUSR1, SIGUSR2, etc."
    echo "Or numeric: 1 (HUP), 2 (INT), 9 (KILL), 15 (TERM), etc."
    exit 1
fi

# Special handling for SIGSTOP/SIGCONT
if [[ "$SIGNAL" == "SIGSTOP" ]]; then
    warn_msg "Use '$SCRIPT_NAME -pause $JOB_ID' instead of sending SIGSTOP"
    exit 1
fi

if [[ "$SIGNAL" == "SIGCONT" ]]; then
    warn_msg "Use '$SCRIPT_NAME -resume $JOB_ID' instead of sending SIGCONT"
    exit 1
fi

# Send signal
kill -"$SIGNAL" "$PID" 2>/dev/null

if [[ $? -eq 0 ]]; then
    echo "📡 Signal $SIGNAL sent to job '$JOB_ID' (PID: $PID)"

    # Log action
    log_action_safe "Sent signal $SIGNAL to job: $JOB_ID (PID: $PID)"

    # Special handling for termination signals
    if [[ "$SIGNAL" == "SIGTERM" || "$SIGNAL" == "SIGKILL" || "$SIGNAL" == "SIGINT" ]]; then
        echo ""
        echo "Job may terminate. Check status with: $SCRIPT_NAME -info $JOB_ID"
    fi
else
    error_msg "Failed to send signal $SIGNAL to job '$JOB_ID'"
    exit 1
fi
