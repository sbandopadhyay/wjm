#!/bin/bash
# resubmit.mod - Resubmit a completed or failed job
# Preserves job parameters and creates a new job

JOB_ID="$1"
FORCE_IMMEDIATE="$2"

# Validate job ID provided
if [[ -z "$JOB_ID" ]]; then
    error_msg "Specify a job ID to resubmit (e.g., $SCRIPT_NAME -resubmit job_001)"
    echo ""
    echo "Usage: $SCRIPT_NAME -resubmit <job_id> [--immediate]"
    echo ""
    echo "Options:"
    echo "  --immediate    Force immediate execution (use -srun instead of -qrun)"
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
    for folder in "$JOB_DIR"/job_*; do
        [[ -d "$folder" ]] && echo "  - $(basename "$folder")"
    done | head -10
    exit 1
fi

# Check if job has finished
if [[ -f "$JOB_PATH/job.pid" ]]; then
    PID=$(cat "$JOB_PATH/job.pid" 2>/dev/null)
    if [[ -n "$PID" ]] && ps -p "$PID" > /dev/null 2>&1; then
        error_msg "Job '$JOB_ID' is still running (PID: $PID)"
        echo ""
        echo "To kill the running job first: $SCRIPT_NAME -kill $JOB_ID"
        exit 1
    fi
fi

# Read original job parameters
if [[ ! -f "$JOB_PATH/job.info" ]]; then
    error_msg "Job metadata file not found: $JOB_PATH/job.info"
    exit 1
fi

if [[ ! -f "$JOB_PATH/command.run" ]]; then
    error_msg "Job command file not found: $JOB_PATH/command.run"
    exit 1
fi

# Extract original parameters
ORIGINAL_NAME=$(grep "^JOB_NAME=" "$JOB_PATH/job.info" 2>/dev/null | head -1 | cut -d= -f2)
ORIGINAL_WEIGHT=$(grep "^WEIGHT=" "$JOB_PATH/job.info" 2>/dev/null | head -1 | cut -d= -f2)
ORIGINAL_GPU=$(grep "^GPU=" "$JOB_PATH/job.info" 2>/dev/null | head -1 | cut -d= -f2)
ORIGINAL_STATUS=$(grep "^STATUS=" "$JOB_PATH/job.info" 2>/dev/null | head -1 | cut -d= -f2)

# Create temporary job file with original command
TEMP_JOB_FILE=$(mktemp "/tmp/resubmit_${JOB_ID}_XXXXXX.run")
if [[ -z "$TEMP_JOB_FILE" ]]; then
    error_msg "Failed to create temporary file"
    exit 1
fi

# Ensure cleanup on exit/interrupt
trap 'rm -f "$TEMP_JOB_FILE"' EXIT INT TERM

# Build job file with metadata
echo "#!/bin/bash" > "$TEMP_JOB_FILE"
[[ -n "$ORIGINAL_WEIGHT" && "$ORIGINAL_WEIGHT" != "N/A" ]] && echo "# WEIGHT: $ORIGINAL_WEIGHT" >> "$TEMP_JOB_FILE"
[[ -n "$ORIGINAL_GPU" && "$ORIGINAL_GPU" != "N/A" ]] && echo "# GPU: $ORIGINAL_GPU" >> "$TEMP_JOB_FILE"
echo "" >> "$TEMP_JOB_FILE"
cat "$JOB_PATH/command.run" >> "$TEMP_JOB_FILE"

# Make executable
chmod +x "$TEMP_JOB_FILE"

# Display resubmit info
echo "Resubmitting job '$JOB_ID'"
echo ""
echo "Original job details:"
echo "  Status:  $ORIGINAL_STATUS"
[[ -n "$ORIGINAL_NAME" ]] && echo "  Name:    $ORIGINAL_NAME"
echo "  Weight:  $ORIGINAL_WEIGHT"
echo "  GPU:     $ORIGINAL_GPU"
echo ""

# Determine submission method
SUBMIT_CMD="-qrun"
if [[ "$FORCE_IMMEDIATE" == "--immediate" ]]; then
    SUBMIT_CMD="-srun"
    echo "Submitting immediately (--immediate flag)"
else
    echo "Submitting to queue (use --immediate to force immediate execution)"
fi
echo ""

# Resubmit with name if original had one
if [[ -n "$ORIGINAL_NAME" ]]; then
    source "$MODULES_DIR/core/$(basename "$SUBMIT_CMD").mod" "$TEMP_JOB_FILE" --name "$ORIGINAL_NAME (resubmit)"
else
    source "$MODULES_DIR/core/$(basename "$SUBMIT_CMD").mod" "$TEMP_JOB_FILE"
fi

# Clean up temporary file
rm -f "$TEMP_JOB_FILE"
