#!/bin/bash
# logs.mod - Easy log file viewing
# Provides convenient access to job log files

JOB_ID="$1"
MODE="${2:---tail}"  # Default to tail mode
LINES="${3:-50}"     # Default 50 lines

# Validate job ID provided
if [[ -z "$JOB_ID" ]]; then
    error_msg "Specify a job ID (e.g., $SCRIPT_NAME -logs job_001)"
    echo ""
    echo "Usage:"
    echo "  $SCRIPT_NAME -logs <job_id>           # View full log"
    echo "  $SCRIPT_NAME -logs <job_id> --tail    # Last 50 lines (default)"
    echo "  $SCRIPT_NAME -logs <job_id> --tail N  # Last N lines"
    echo "  $SCRIPT_NAME -logs <job_id> --head    # First 50 lines"
    echo "  $SCRIPT_NAME -logs <job_id> --head N  # First N lines"
    echo "  $SCRIPT_NAME -logs <job_id> --follow  # Follow mode (live updates)"
    echo "  $SCRIPT_NAME -logs <job_id> --all     # Show entire log"
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
    echo ""
    echo "Available jobs:"
    $SCRIPT_NAME -list | grep -E "job_[0-9]{3}" | head -5
    exit 1
fi

# Find log file
LOG_FILE=$(ls "$JOB_PATH"/*.log 2>/dev/null | head -1)

if [[ ! -f "$LOG_FILE" ]]; then
    error_msg "No log file found for job '$JOB_ID'"
    echo ""
    echo "Job directory: $JOB_PATH"
    echo "Expected log: $JOB_PATH/$JOB_ID.log"
    exit 1
fi

# Get job info for header
JOB_STATUS="UNKNOWN"
JOB_USER="N/A"
START_TIME="N/A"
if [[ -f "$JOB_PATH/job.info" ]]; then
    JOB_STATUS=$(grep "^STATUS=" "$JOB_PATH/job.info" | head -1 | cut -d= -f2)
    JOB_USER=$(grep "^USER=" "$JOB_PATH/job.info" | head -1 | cut -d= -f2)
    START_TIME=$(grep "^START_TIME=" "$JOB_PATH/job.info" | head -1 | cut -d= -f2)
fi

# Display header
echo "Log File: $JOB_ID"
echo "=============================================="
echo "User:     $JOB_USER"
echo "Status:   $JOB_STATUS"
echo "Started:  $START_TIME"
echo "Log:      $LOG_FILE"
echo "=============================================="
echo ""

# Parse mode and display log
case "$MODE" in
    --tail)
        # Show last N lines
        if [[ -n "$3" && "$3" =~ ^[0-9]+$ ]]; then
            LINES="$3"
        fi
        echo "Showing last $LINES lines:"
        echo ""
        tail -n "$LINES" "$LOG_FILE"
        ;;

    --head)
        # Show first N lines
        if [[ -n "$3" && "$3" =~ ^[0-9]+$ ]]; then
            LINES="$3"
        fi
        echo "Showing first $LINES lines:"
        echo ""
        head -n "$LINES" "$LOG_FILE"
        ;;

    --follow|-f)
        # Follow mode (live updates)
        echo "Following log (Ctrl+C to exit):"
        echo ""
        tail -f "$LOG_FILE"
        ;;

    --all|--full)
        # Show entire log
        echo "Full log contents:"
        echo ""
        cat "$LOG_FILE"
        ;;

    *)
        # Default: same as --tail 50
        echo "Showing last 50 lines (use --help for more options):"
        echo ""
        tail -n 50 "$LOG_FILE"
        ;;
esac

echo ""
echo "=============================================="
echo "Tip: Use '$SCRIPT_NAME -logs $JOB_ID --follow' for live updates"
