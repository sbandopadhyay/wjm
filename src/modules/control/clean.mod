#!/bin/bash
# clean.mod - Clean up completed/failed jobs
# Removes job directories to free up space

CLEAN_TYPE="$1"

# Display usage if no argument
if [[ -z "$CLEAN_TYPE" ]]; then
    echo "Job Cleanup Utility"
    echo ""
    echo "Usage: $SCRIPT_NAME -clean <type>"
    echo ""
    echo "Types:"
    echo "  failed      Remove only failed jobs"
    echo "  completed   Remove only successfully completed jobs"
    echo "  all         Remove all finished jobs (completed + failed)"
    echo "  old         Remove jobs older than 7 days"
    echo ""
    echo "Examples:"
    echo "  $SCRIPT_NAME -clean failed      # Remove failed jobs"
    echo "  $SCRIPT_NAME -clean all         # Remove all finished jobs"
    echo ""
    exit 0
fi

# Count and collect jobs to clean
failed_jobs=()
completed_jobs=()
old_jobs=()

# Prevent unbounded array growth
MAX_JOBS_PER_CLEAN=1000

# Validate date calculation
cutoff_date=$(date -d '7 days ago' +%s 2>/dev/null || date -v -7d +%s 2>/dev/null)
if [[ -z "$cutoff_date" || ! "$cutoff_date" =~ ^[0-9]+$ ]]; then
    # Date calculation failed (unsupported platform or invalid date)
    cutoff_date=""
    if [[ "$1" == "old" ]]; then
        warn_msg "Cannot calculate dates on this platform - 'old' cleanup unavailable"
        echo ""
        echo "Available cleanup types: failed, completed, all"
        exit 1
    fi
fi

for folder in "$JOB_DIR"/job_*; do
    [[ ! -d "$folder" ]] && continue

    job_name=$(basename "$folder")

    # Skip running jobs
    if [[ -f "$folder/job.pid" ]]; then
        PID=$(cat "$folder/job.pid" 2>/dev/null)
        if [[ -n "$PID" ]] && ps -p "$PID" > /dev/null 2>&1; then
            continue
        fi
    fi

    # Get status
    status="UNKNOWN"
    submit_time=""
    if [[ -f "$folder/job.info" ]]; then
        status=$(grep "^STATUS=" "$folder/job.info" | head -1 | cut -d= -f2)
        submit_time=$(grep "^SUBMIT_TIME=" "$folder/job.info" | head -1 | cut -d= -f2)
    fi

    # Check limit BEFORE adding to prevent overshoot
    total_jobs=$((${#failed_jobs[@]} + ${#completed_jobs[@]} + ${#old_jobs[@]}))
    if [[ $total_jobs -ge $MAX_JOBS_PER_CLEAN ]]; then
        warn_msg "Reached maximum jobs per clean ($MAX_JOBS_PER_CLEAN). Run again to continue."
        break
    fi

    # Categorize job (now we're guaranteed not to exceed limit)
    if [[ "$status" == "FAILED" || "$status" == "KILLED" ]]; then
        failed_jobs+=("$job_name")
    elif [[ "$status" == "COMPLETED" ]]; then
        completed_jobs+=("$job_name")
    fi

    # Check if old (if we can parse the date)
    if [[ -n "$submit_time" && -n "$cutoff_date" ]]; then
        job_timestamp=$(date -d "$submit_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$submit_time" +%s 2>/dev/null)
        if [[ -n "$job_timestamp" && "$job_timestamp" -lt "$cutoff_date" ]]; then
            old_jobs+=("$job_name")
        fi
    fi
done

# Determine which jobs to clean
jobs_to_clean=()
case "$CLEAN_TYPE" in
    "failed")
        jobs_to_clean=("${failed_jobs[@]}")
        echo "Cleaning failed jobs..."
        ;;
    "completed")
        jobs_to_clean=("${completed_jobs[@]}")
        echo "Cleaning completed jobs..."
        ;;
    "all")
        jobs_to_clean=("${failed_jobs[@]}" "${completed_jobs[@]}")
        echo "Cleaning all finished jobs..."
        ;;
    "old")
        jobs_to_clean=("${old_jobs[@]}")
        echo "Cleaning jobs older than 7 days..."
        ;;
    *)
        error_msg "Unknown clean type: '$CLEAN_TYPE'"
        echo ""
        echo "Valid types: failed, completed, all, old"
        exit 1
        ;;
esac

# Check if there are jobs to clean
if [[ ${#jobs_to_clean[@]} -eq 0 ]]; then
    echo "[OK] No jobs to clean"
    exit 0
fi

# Display what will be removed
echo ""
echo "Jobs to be removed (${#jobs_to_clean[@]} total):"
for job in "${jobs_to_clean[@]}"; do
    status="N/A"
    if [[ -f "$JOB_DIR/$job/job.info" ]]; then
        status=$(grep "^STATUS=" "$JOB_DIR/$job/job.info" | head -1 | cut -d= -f2)
    fi
    echo "  - $job ($status)"
done | head -20

if [[ ${#jobs_to_clean[@]} -gt 20 ]]; then
    echo "  ... and $((${#jobs_to_clean[@]} - 20)) more"
fi

# Confirm deletion
echo ""
read -p "Delete these ${#jobs_to_clean[@]} jobs? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

# Perform cleanup
echo ""
echo "️  Removing jobs..."
removed_count=0

for job in "${jobs_to_clean[@]}"; do
    job_path="$JOB_DIR/$job"
    if [[ -d "$job_path" ]]; then
        rm -rf "$job_path"
        removed_count=$((removed_count + 1))
        echo "  [OK] Removed $job"
    fi
done

echo ""
echo "Cleanup complete: Removed $removed_count jobs"
echo " Freed disk space: $(du -sh "$JOB_DIR" 2>/dev/null | cut -f1) remaining in job directory"
