#!/bin/bash
# logmanager.mod - Smart Log Management
# Provides log rotation, compression, and cleanup functionality

# LOG SIZE CHECKING

# Check if a log file exceeds the maximum size limit
# Returns: 0 if under limit, 1 if over limit
check_log_size() {
    local log_file="$1"

    # If MAX_LOG_SIZE_MB is 0 or unset, no size limit
    [[ -z "$MAX_LOG_SIZE_MB" || "$MAX_LOG_SIZE_MB" -eq 0 ]] && return 0

    # If log file doesn't exist, no problem
    [[ ! -f "$log_file" ]] && return 0

    # Get file size in MB
    local size_mb=$(du -m "$log_file" 2>/dev/null | cut -f1)
    [[ -z "$size_mb" ]] && return 0

    # Check if size exceeds limit
    if [[ $size_mb -ge $MAX_LOG_SIZE_MB ]]; then
        return 1  # Over limit
    fi

    return 0  # Under limit
}

# LOG ROTATION

# Rotate log files: log -> log.1 -> log.2 -> ... -> log.N
rotate_log() {
    local log_file="$1"

    # If log doesn't exist, nothing to rotate
    [[ ! -f "$log_file" ]] && return 0

    # Default rotation count if not set
    local rotation_count=${LOG_ROTATION_COUNT:-5}

    # Remove oldest log if it exists
    if [[ -f "${log_file}.${rotation_count}" ]]; then
        rm -f "${log_file}.${rotation_count}"
    fi
    if [[ -f "${log_file}.${rotation_count}.gz" ]]; then
        rm -f "${log_file}.${rotation_count}.gz"
    fi

    # Rotate existing logs (from N-1 down to 1)
    for ((i=rotation_count-1; i>=1; i--)); do
        if [[ -f "${log_file}.${i}" ]]; then
            mv "${log_file}.${i}" "${log_file}.$((i+1))"
        fi
        if [[ -f "${log_file}.${i}.gz" ]]; then
            mv "${log_file}.${i}.gz" "${log_file}.$((i+1)).gz"
        fi
    done

    # Move current log to .1
    mv "$log_file" "${log_file}.1"

    # Create new empty log file
    touch "$log_file"

    echo "Log rotated: $(basename "$log_file") (size exceeded ${MAX_LOG_SIZE_MB}MB)"
}

# LOG COMPRESSION

# Compress rotated log files to save space
compress_rotated_logs() {
    local log_file="$1"

    # If compression is disabled, skip
    [[ "$LOG_COMPRESSION_ENABLED" != "yes" ]] && return 0

    # Check if gzip is available
    if ! command -v gzip &> /dev/null; then
        return 0  # Skip compression if gzip not available
    fi

    # Compress rotated logs (but not the current log)
    local rotation_count=${LOG_ROTATION_COUNT:-5}
    for ((i=1; i<=rotation_count; i++)); do
        if [[ -f "${log_file}.${i}" && ! -f "${log_file}.${i}.gz" ]]; then
            gzip -9 "${log_file}.${i}" 2>/dev/null
            [[ $? -eq 0 ]] && echo "   Compressed: $(basename "${log_file}.${i}")"
        fi
    done
}

# LOG CLEANUP

# Clean up old log files based on age
cleanup_old_logs() {
    local job_dir="$1"

    # If LOG_CLEANUP_DAYS is 0 or unset, no automatic cleanup
    [[ -z "$LOG_CLEANUP_DAYS" || "$LOG_CLEANUP_DAYS" -eq 0 ]] && return 0

    # Find and remove log files older than LOG_CLEANUP_DAYS
    local cleaned=0

    # Clean up *.log files
    for log_file in "$job_dir"/*.log "$job_dir"/*.log.* "$job_dir"/*.log.*.gz; do
        [[ ! -f "$log_file" ]] && continue

        # Check file age (in days) - with proper error handling
        local file_mtime
        file_mtime=$(stat -c %Y "$log_file" 2>/dev/null || stat -f %m "$log_file" 2>/dev/null)

        # Skip if stat failed to get modification time
        [[ -z "$file_mtime" || ! "$file_mtime" =~ ^[0-9]+$ ]] && continue

        local current_time=$(date +%s)
        local age_days=$(( (current_time - file_mtime) / 86400 ))

        if [[ $age_days -gt $LOG_CLEANUP_DAYS ]]; then
            rm -f "$log_file"
            cleaned=$((cleaned + 1))
        fi
    done

    [[ $cleaned -gt 0 ]] && echo "️  Cleaned up $cleaned old log files (older than ${LOG_CLEANUP_DAYS} days)"
}

# SMART LOG MANAGEMENT - MAIN FUNCTION

# Manage log for a job: check size, rotate if needed, compress old logs
manage_job_log() {
    local log_file="$1"

    # Check if log size exceeds limit
    if ! check_log_size "$log_file"; then
        # Rotate the log
        rotate_log "$log_file"

        # Compress rotated logs
        compress_rotated_logs "$log_file"
    fi
}

# VALIDATION

# Validate log management configuration
validate_log_config() {
    # Validate MAX_LOG_SIZE_MB
    if [[ -n "$MAX_LOG_SIZE_MB" && ! "$MAX_LOG_SIZE_MB" =~ ^[0-9]+$ ]]; then
        warn_msg "Invalid MAX_LOG_SIZE_MB in config, using 100"
        MAX_LOG_SIZE_MB=100
    fi

    # Validate LOG_ROTATION_COUNT
    if [[ -n "$LOG_ROTATION_COUNT" && ! "$LOG_ROTATION_COUNT" =~ ^[0-9]+$ ]]; then
        warn_msg "Invalid LOG_ROTATION_COUNT in config, using 5"
        LOG_ROTATION_COUNT=5
    fi

    # Validate LOG_CLEANUP_DAYS
    if [[ -n "$LOG_CLEANUP_DAYS" && ! "$LOG_CLEANUP_DAYS" =~ ^[0-9]+$ ]]; then
        warn_msg "Invalid LOG_CLEANUP_DAYS in config, using 30"
        LOG_CLEANUP_DAYS=30
    fi

    # Validate LOG_COMPRESSION_ENABLED
    if [[ -n "$LOG_COMPRESSION_ENABLED" && "$LOG_COMPRESSION_ENABLED" != "yes" && "$LOG_COMPRESSION_ENABLED" != "no" ]]; then
        warn_msg "Invalid LOG_COMPRESSION_ENABLED in config, using 'yes'"
        LOG_COMPRESSION_ENABLED="yes"
    fi
}
