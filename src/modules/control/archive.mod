#!/bin/bash
# archive.mod - Archive completed jobs
# SECURITY FIX: Safe directory iteration instead of ls

get_next_archive_index() {
    local last_archive=0

    # Use glob instead of ls for safety
    for dir in "$ARCHIVE_DIR"/[0-9][0-9][0-9]; do
        [[ ! -d "$dir" ]] && continue
        local idx="${dir##*/}"
        # Validate it's numeric
        if [[ "$idx" =~ ^[0-9]+$ ]] && [[ $idx -gt $last_archive ]]; then
            last_archive=$idx
        fi
    done

    local next_index=$((last_archive + 1))
    printf "%03d" "$next_index"
}

ARCHIVE_BATCH=$(get_next_archive_index)
ARCHIVE_PATH="$ARCHIVE_DIR/$ARCHIVE_BATCH"
mkdir -p "$ARCHIVE_PATH"

echo "Archiving completed jobs to batch $ARCHIVE_BATCH..."
archived_jobs=0

# Glob safety check added
for folder in "$JOB_DIR"/job_*; do
    [[ ! -d "$folder" ]] && continue  # Skip if glob didn't match
    if [[ ! -f "$folder/job.pid" ]]; then
        # Compress logs before archiving (if enabled)
        if [[ "$LOG_COMPRESSION_ENABLED" == "yes" ]] && command -v gzip &> /dev/null; then
            for log_file in "$folder"/*.log; do
                [[ -f "$log_file" && ! -f "${log_file}.gz" ]] && gzip -9 "$log_file" 2>/dev/null
            done
        fi

        mv "$folder" "$ARCHIVE_PATH/" || { echo "Failed to archive $(basename "$folder")"; exit 1; }
        echo "Moved $(basename "$folder") to archive batch $ARCHIVE_BATCH."
        archived_jobs=$((archived_jobs + 1))
    fi
done

if [[ "$archived_jobs" -gt 0 ]]; then
    echo "Archive complete! View old jobs in $ARCHIVE_PATH/"
    log_action_safe "Archived $archived_jobs jobs to $ARCHIVE_PATH"  # SECURITY FIX: Use thread-safe logging
else
    echo "No completed jobs found to archive."
fi

# AUTO-CLEANUP OLD ARCHIVES

cleanup_old_archives() {
    # If MAX_ARCHIVE_BATCHES is 0 or unset, keep all archives
    [[ -z "$MAX_ARCHIVE_BATCHES" || "$MAX_ARCHIVE_BATCHES" -eq 0 ]] && return 0

    # Count archive batches
    local archive_count=0
    for dir in "$ARCHIVE_DIR"/[0-9][0-9][0-9]; do
        [[ -d "$dir" ]] && archive_count=$((archive_count + 1))
    done

    # If we're within limits, no cleanup needed
    [[ $archive_count -le $MAX_ARCHIVE_BATCHES ]] && return 0

    # Calculate how many to remove
    local to_remove=$((archive_count - MAX_ARCHIVE_BATCHES))

    echo ""
    echo "️  Cleaning up old archive batches (keeping last $MAX_ARCHIVE_BATCHES)..."

    # Get oldest batches and remove them
    local removed=0
    for dir in "$ARCHIVE_DIR"/[0-9][0-9][0-9]; do
        [[ ! -d "$dir" ]] && continue

        if [[ $removed -lt $to_remove ]]; then
            local batch_name=$(basename "$dir")
            echo "  ️  Removing old archive batch: $batch_name"
            rm -rf "$dir"
            removed=$((removed + 1))
        else
            break
        fi
    done

    echo "Cleaned up $removed old archive batches"
    log_action_safe "Auto-cleanup: Removed $removed old archive batches (keeping last $MAX_ARCHIVE_BATCHES)"
}

# Run cleanup after archiving
cleanup_old_archives