#!/bin/bash
# info.mod - Detailed job information display
# Shows all information about a specific job

JOB_ID="$1"

# Validate job ID provided
if [[ -z "$JOB_ID" ]]; then
    error_msg "Specify a job ID (e.g., $SCRIPT_NAME -info job_001)"
    echo ""
    echo "Usage: $SCRIPT_NAME -info <job_id>"
    echo ""
    echo "To see all jobs: $SCRIPT_NAME -list"
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
    if command -v "$SCRIPT_NAME" >/dev/null 2>&1; then
        "$SCRIPT_NAME" -list | grep -E "job_[0-9]{3}" | head -5
    fi
    exit 1
fi

# Read job information
JOB_FILE="N/A"
JOB_FRIENDLY_NAME=""
USER="N/A"
SUBMIT_TIME="N/A"
QUEUE_TIME="N/A"
START_TIME="N/A"
END_TIME="N/A"
STATUS="UNKNOWN"
WEIGHT="N/A"
GPU="N/A"
PID="N/A"
EXIT_CODE="N/A"

# Add error checking for file reads
if [[ -f "$JOB_PATH/job.info" ]]; then
    # Read all fields with fallback to defaults if grep fails
    JOB_FILE=$(grep "^JOB_FILE=" "$JOB_PATH/job.info" 2>/dev/null | head -1 | cut -d= -f2) || JOB_FILE="N/A"
    JOB_FRIENDLY_NAME=$(grep "^JOB_NAME=" "$JOB_PATH/job.info" 2>/dev/null | head -1 | cut -d= -f2) || JOB_FRIENDLY_NAME=""
    USER=$(grep "^USER=" "$JOB_PATH/job.info" 2>/dev/null | head -1 | cut -d= -f2) || USER="N/A"
    SUBMIT_TIME=$(grep "^SUBMIT_TIME=" "$JOB_PATH/job.info" 2>/dev/null | head -1 | cut -d= -f2) || SUBMIT_TIME="N/A"
    QUEUE_TIME=$(grep "^QUEUE_TIME=" "$JOB_PATH/job.info" 2>/dev/null | head -1 | cut -d= -f2) || QUEUE_TIME="N/A"
    START_TIME=$(grep "^START_TIME=" "$JOB_PATH/job.info" 2>/dev/null | head -1 | cut -d= -f2) || START_TIME="N/A"
    END_TIME=$(grep "^END_TIME=" "$JOB_PATH/job.info" 2>/dev/null | head -1 | cut -d= -f2) || END_TIME="N/A"
    STATUS=$(grep "^STATUS=" "$JOB_PATH/job.info" 2>/dev/null | head -1 | cut -d= -f2) || STATUS="UNKNOWN"
    WEIGHT=$(grep "^WEIGHT=" "$JOB_PATH/job.info" 2>/dev/null | head -1 | cut -d= -f2) || WEIGHT="N/A"
    GPU=$(grep "^GPU=" "$JOB_PATH/job.info" 2>/dev/null | head -1 | cut -d= -f2) || GPU="N/A"

    # Ensure non-empty values
    [[ -z "$JOB_FILE" ]] && JOB_FILE="N/A"
    [[ -z "$USER" ]] && USER="N/A"
    [[ -z "$SUBMIT_TIME" ]] && SUBMIT_TIME="N/A"
    [[ -z "$QUEUE_TIME" ]] && QUEUE_TIME="N/A"
    [[ -z "$START_TIME" ]] && START_TIME="N/A"
    [[ -z "$END_TIME" ]] && END_TIME="N/A"
    [[ -z "$STATUS" ]] && STATUS="UNKNOWN"
    [[ -z "$WEIGHT" ]] && WEIGHT="N/A"
    [[ -z "$GPU" ]] && GPU="N/A"
fi

if [[ -f "$JOB_PATH/job.pid" ]]; then
    PID=$(cat "$JOB_PATH/job.pid" 2>/dev/null)
fi

if [[ -f "$JOB_PATH/exit.code" ]]; then
    EXIT_CODE=$(cat "$JOB_PATH/exit.code" 2>/dev/null)
fi

# Read command
COMMAND="N/A"
if [[ -f "$JOB_PATH/command.run" ]]; then
    # Read first 5 lines safely
    COMMAND=$(head -5 "$JOB_PATH/command.run" 2>/dev/null)
    if [[ -n "$COMMAND" ]]; then
        # Convert newlines to spaces
        COMMAND=$(echo "$COMMAND" | tr '\n' ' ')
        # Truncate to 100 characters if needed
        if [[ ${#COMMAND} -gt 100 ]]; then
            COMMAND="${COMMAND:0:100}..."
        fi
    else
        COMMAND="N/A"
    fi
fi

# Calculate comprehensive durations
QUEUE_DURATION="N/A"
RUN_DURATION="N/A"
TOTAL_DURATION="N/A"

# Determine end time for calculations (now if running, END_TIME if completed)
CALC_END_TIME="$END_TIME"
if [[ "$STATUS" == "RUNNING" ]]; then
    CALC_END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
fi

# Calculate queue duration (if job was queued)
if [[ "$QUEUE_TIME" != "N/A" && "$QUEUE_TIME" != "" ]]; then
    QUEUE_DURATION=$(calculate_queue_duration "$SUBMIT_TIME" "$QUEUE_TIME")
fi

# Calculate run duration
if [[ "$START_TIME" != "N/A" ]]; then
    if [[ "$CALC_END_TIME" != "N/A" ]]; then
        RUN_DURATION=$(calculate_run_duration "$START_TIME" "$CALC_END_TIME")
    else
        RUN_DURATION=$(calculate_run_duration "$START_TIME")
    fi
fi

# Calculate total duration (submit to end/now)
if [[ "$SUBMIT_TIME" != "N/A" ]]; then
    if [[ "$CALC_END_TIME" != "N/A" ]]; then
        TOTAL_DURATION=$(calculate_total_duration "$SUBMIT_TIME" "$CALC_END_TIME")
    else
        TOTAL_DURATION=$(calculate_total_duration "$SUBMIT_TIME")
    fi
fi

# Find log file
LOG_FILE=$(ls "$JOB_PATH"/*.log 2>/dev/null | head -1)
LOG_SIZE="N/A"
if [[ -f "$LOG_FILE" ]]; then
    LOG_SIZE=$(du -h "$LOG_FILE" 2>/dev/null | cut -f1)
fi

# Check if job is running
IS_RUNNING=false
if [[ "$STATUS" == "RUNNING" && -n "$PID" && "$PID" != "N/A" ]]; then
    if ps -p "$PID" >/dev/null 2>&1; then
        IS_RUNNING=true
    fi
fi

# Display header
echo "======================================================"
if [[ -n "$JOB_FRIENDLY_NAME" ]]; then
    echo "Job Information: $JOB_ID [$JOB_FRIENDLY_NAME]"
else
    echo "Job Information: $JOB_ID"
fi
echo "======================================================"
echo ""

# Status indicator
case "$STATUS" in
    RUNNING)
        if [[ "$IS_RUNNING" == true ]]; then
            echo "Status:        RUNNING"
        else
            echo "Status:        RUNNING (stale PID)"
        fi
        ;;
    COMPLETED)
        echo "Status:        COMPLETED"
        ;;
    FAILED)
        echo "Status:        FAILED"
        ;;
    KILLED)
        echo "Status:         KILLED"
        ;;
    *)
        echo "Status:        $STATUS"
        ;;
esac

# Job details
echo "User:          $USER"
echo "Job File:      $JOB_FILE"
echo ""

# Comprehensive timing information
echo "Submitted:     $SUBMIT_TIME"
if [[ "$QUEUE_TIME" != "N/A" && "$QUEUE_TIME" != "" ]]; then
    echo "Queued:        $QUEUE_TIME"
    echo "Queue Time:    $QUEUE_DURATION"
fi
echo "Started:       $START_TIME"
if [[ "$END_TIME" != "N/A" ]]; then
    echo "Ended:         $END_TIME"
fi
echo "Run Time:      $RUN_DURATION"
if [[ "$QUEUE_DURATION" != "N/A" ]]; then
    echo "Total Time:    $TOTAL_DURATION (queue + run)"
fi
echo ""

# Resource information
echo "Weight:        $WEIGHT"
echo "GPU:           $GPU"
if [[ "$PID" != "N/A" ]]; then
    echo "PID:           $PID"
fi
if [[ "$EXIT_CODE" != "N/A" ]]; then
    if [[ "$EXIT_CODE" == "0" ]]; then
        echo "Exit Code:     $EXIT_CODE (success)"
    else
        echo "Exit Code:     $EXIT_CODE (failure)"
    fi
fi
echo ""

# File locations
echo "Job Directory: $JOB_PATH"
if [[ -f "$LOG_FILE" ]]; then
    echo "Log File:      $LOG_FILE"
    echo "Log Size:      $LOG_SIZE"
fi
echo ""

# Command (truncated)
echo "Command:       $COMMAND"
echo ""

# Log preview
if [[ -f "$LOG_FILE" ]]; then
    LOG_LINES=$(wc -l < "$LOG_FILE" 2>/dev/null)
    echo "======================================================"
    echo "Log Preview (last 10 lines of $LOG_LINES total):"
    echo "======================================================"
    echo ""
    tail -n 10 "$LOG_FILE" 2>/dev/null
    echo ""
else
    echo "======================================================"
    echo "No log file found"
    echo "======================================================"
    echo ""
fi

# Helpful commands
echo "Useful commands:"
echo "   View full log:       $SCRIPT_NAME -logs $JOB_ID"
echo "   Follow log live:     $SCRIPT_NAME -logs $JOB_ID --follow"
if [[ "$STATUS" == "FAILED" || "$STATUS" == "KILLED" ]]; then
    echo "   Resubmit job:        $SCRIPT_NAME -resubmit $JOB_ID"
fi
if [[ "$STATUS" == "RUNNING" ]]; then
    echo "   Kill job:            $SCRIPT_NAME -kill $JOB_ID"
    echo "   Monitor live:        $SCRIPT_NAME -watch $JOB_ID"
fi
echo ""
