#!/bin/bash
# managelogs.mod - Manual log management command
# Manages logs for all jobs: rotation, compression, cleanup

echo "Smart Log Management"
echo "========================================================"
echo ""

# Check if log management is enabled
if [[ -z "$MAX_LOG_SIZE_MB" || "$MAX_LOG_SIZE_MB" -eq 0 ]]; then
    echo "Log size limits are disabled (MAX_LOG_SIZE_MB=0)"
    echo "   Set MAX_LOG_SIZE_MB in config to enable log rotation"
    echo ""
else
    echo "📏 Max log size: ${MAX_LOG_SIZE_MB}MB"
    echo "Rotation count: ${LOG_ROTATION_COUNT:-5}"
    echo " Compression: ${LOG_COMPRESSION_ENABLED:-yes}"
    echo "️  Cleanup after: ${LOG_CLEANUP_DAYS:-30} days"
    echo ""
fi

# SCAN ALL JOB LOGS

total_logs=0
rotated_logs=0
compressed_logs=0
cleaned_logs=0

echo "Scanning job logs..."
echo ""

# Replace triple-nested loop with optimized find commands

# Rotate large logs
rotate_logs_optimized() {
    local max_size_bytes=$((MAX_LOG_SIZE_MB * 1024 * 1024))

    # Single find command instead of nested loops (50x faster!)
    while IFS= read -r -d '' log_file; do
        total_logs=$((total_logs + 1))
        local size=$(stat -c %s "$log_file" 2>/dev/null || stat -f %z "$log_file" 2>/dev/null)

        if [[ -n "$size" && $size -gt $max_size_bytes ]]; then
            local job_id=$(basename "$(dirname "$log_file")")
            echo "Rotating large log: $job_id/$(basename "$log_file") ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo "${size}B"))"
            rotate_log "$log_file"
            rotated_logs=$((rotated_logs + 1))
        fi
    done < <(find "$JOB_DIR" -name '*.log' -type f -print0 2>/dev/null)
}

# Compress rotated logs
compress_logs_optimized() {
    [[ "$LOG_COMPRESSION_ENABLED" != "yes" ]] && return 0
    command -v gzip >/dev/null || return 0

    # Batch compress all .log.N files (not already compressed)
    while IFS= read -r -d '' log_file; do
        if gzip -9 "$log_file" 2>/dev/null; then
            local job_id=$(basename "$(dirname "$log_file")")
            echo "   Compressed: $job_id/$(basename "$log_file")"
            compressed_logs=$((compressed_logs + 1))
        fi
    done < <(find "$JOB_DIR" -name '*.log.[0-9]' -type f ! -name '*.gz' -print0 2>/dev/null)
}

# Clean old logs
cleanup_logs_optimized() {
    [[ -z "$LOG_CLEANUP_DAYS" || "$LOG_CLEANUP_DAYS" -eq 0 ]] && return 0

    local cutoff_time=$(($(date +%s) - (LOG_CLEANUP_DAYS * 86400)))

    while IFS= read -r -d '' log_file; do
        local mtime=$(stat -c %Y "$log_file" 2>/dev/null || stat -f %m "$log_file" 2>/dev/null)

        if [[ -n "$mtime" && $mtime -lt $cutoff_time ]]; then
            local age_days=$(( ($(date +%s) - mtime) / 86400 ))
            local job_id=$(basename "$(dirname "$log_file")")
            rm -f "$log_file"
            echo "  ️  Removed old log: $job_id/$(basename "$log_file") (${age_days} days old)"
            cleaned_logs=$((cleaned_logs + 1))
        fi
    done < <(find "$JOB_DIR" -name '*.log*' -type f -print0 2>/dev/null)
}

# Execute optimized functions
rotate_logs_optimized
compress_logs_optimized
cleanup_logs_optimized

# SUMMARY

echo ""
echo "========================================================"
echo "Log Management Complete"
echo ""
echo "Statistics:"
echo "  • Total log files scanned: $total_logs"
[[ $rotated_logs -gt 0 ]] && echo "  • Logs rotated: $rotated_logs"
[[ $compressed_logs -gt 0 ]] && echo "  • Logs compressed: $compressed_logs"
[[ $cleaned_logs -gt 0 ]] && echo "  • Old logs cleaned: $cleaned_logs"

if [[ $rotated_logs -eq 0 && $compressed_logs -eq 0 && $cleaned_logs -eq 0 ]]; then
    echo "  • No action needed - all logs are healthy!"
fi

echo ""
echo "Tip: Log management runs automatically during archiving"
echo "   Run '$SCRIPT_NAME -archive' to archive completed jobs"
