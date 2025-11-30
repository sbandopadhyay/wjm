#!/bin/bash
# stats.mod - Job Statistics & Analytics
# Provides comprehensive statistics about job execution

echo "Job Scheduler Statistics"
echo "========================================================"
echo ""

# COUNT JOBS BY STATUS

total_jobs=0
running_jobs=0
queued_jobs=0
completed_jobs=0
failed_jobs=0
killed_jobs=0

# Count active jobs
for job_dir in "$JOB_DIR"/job_*; do
    [[ ! -d "$job_dir" ]] && continue

    total_jobs=$((total_jobs + 1))

    if [[ -f "$job_dir/job.info" ]]; then
        status=$(grep "^STATUS=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)

        case "$status" in
            RUNNING) running_jobs=$((running_jobs + 1)) ;;
            QUEUED) queued_jobs=$((queued_jobs + 1)) ;;
            COMPLETED) completed_jobs=$((completed_jobs + 1)) ;;
            FAILED) failed_jobs=$((failed_jobs + 1)) ;;
            KILLED) killed_jobs=$((killed_jobs + 1)) ;;
        esac
    fi
done

# Count archived jobs
archived_jobs=0
if [[ -d "$ARCHIVE_DIR" ]]; then
    for archive_batch in "$ARCHIVE_DIR"/[0-9][0-9][0-9]; do
        [[ ! -d "$archive_batch" ]] && continue

        for job_dir in "$archive_batch"/job_*; do
            [[ ! -d "$job_dir" ]] && continue
            archived_jobs=$((archived_jobs + 1))
        done
    done
fi

# Display job counts
echo "Job Counts:"
echo "  Total Jobs:     $total_jobs"
echo "  ├─ Running:     $running_jobs"
echo "  ├─ Queued:      $queued_jobs"
echo "  ├─ Completed:   $completed_jobs"
echo "  ├─ Failed:      $failed_jobs"
echo "  └─ Killed:      $killed_jobs"
echo "  Archived:       $archived_jobs"
echo ""

# RESOURCE UTILIZATION

total_weight=0
allocated_gpus=""

for job_dir in "$JOB_DIR"/job_*; do
    [[ ! -d "$job_dir" ]] && continue
    [[ ! -f "$job_dir/job.pid" ]] && continue

    # Check if still running
    pid=$(cat "$job_dir/job.pid" 2>/dev/null)
    if [[ -n "$pid" ]] && ps -p "$pid" > /dev/null 2>&1; then
        # Get weight
        weight=$(grep "^WEIGHT=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
        [[ -n "$weight" && "$weight" =~ ^[0-9]+$ ]] && total_weight=$((total_weight + weight))

        # Get GPU
        gpu=$(grep "^GPU=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
        if [[ -n "$gpu" && "$gpu" != "N/A" ]]; then
            allocated_gpus="$allocated_gpus,$gpu"
        fi
    fi
done

# Calculate utilization percentages
weight_percent=0
job_percent=0

if [[ "$MAX_TOTAL_WEIGHT" -gt 0 ]]; then
    weight_percent=$((total_weight * 100 / MAX_TOTAL_WEIGHT))
fi

if [[ "$MAX_CONCURRENT_JOBS" -gt 0 ]]; then
    job_percent=$((running_jobs * 100 / MAX_CONCURRENT_JOBS))
fi

echo " Resource Utilization:"
echo "  Weight: $total_weight / $MAX_TOTAL_WEIGHT (${weight_percent}%)"
echo "  Jobs:   $running_jobs / $MAX_CONCURRENT_JOBS (${job_percent}%)"

if [[ -n "$allocated_gpus" ]]; then
    # Remove leading comma and duplicates
    allocated_gpus=$(echo "$allocated_gpus" | sed 's/^,//' | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
    echo "  GPUs:   $allocated_gpus"
else
    echo "  GPUs:   None allocated"
fi
echo ""

# SUCCESS RATE ANALYSIS

if [[ $((completed_jobs + failed_jobs)) -gt 0 ]]; then
    success_rate=$((completed_jobs * 100 / (completed_jobs + failed_jobs)))

    echo "Success Rate:"
    echo "  Success: $completed_jobs jobs"
    echo "  Failed:  $failed_jobs jobs"
    echo "  Rate:    ${success_rate}%"
    echo ""
fi

# PRIORITY DISTRIBUTION

urgent_count=0
high_count=0
normal_count=0
low_count=0

for job_dir in "$JOB_DIR"/job_*; do
    [[ ! -d "$job_dir" ]] && continue
    [[ ! -f "$job_dir/job.info" ]] && continue

    priority=$(grep "^PRIORITY=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)

    case "$priority" in
        urgent) urgent_count=$((urgent_count + 1)) ;;
        high) high_count=$((high_count + 1)) ;;
        low) low_count=$((low_count + 1)) ;;
        *) normal_count=$((normal_count + 1)) ;;
    esac
done

if [[ $total_jobs -gt 0 ]]; then
    echo "Priority Distribution:"
    echo "  Urgent:  $urgent_count"
    echo "  High:    $high_count"
    echo "  Normal:  $normal_count"
    echo "  Low:     $low_count"
    echo ""
fi

# AVERAGE EXECUTION TIMES

total_runtime=0
runtime_count=0
total_queue_time=0
queue_count=0

for job_dir in "$JOB_DIR"/job_*; do
    [[ ! -d "$job_dir" ]] && continue
    [[ ! -f "$job_dir/job.info" ]] && continue

    status=$(grep "^STATUS=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)

    if [[ "$status" == "COMPLETED" || "$status" == "FAILED" ]]; then
        start_time=$(grep "^START_TIME=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
        end_time=$(grep "^END_TIME=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)

        if [[ -n "$start_time" && -n "$end_time" ]]; then
            start_epoch=$(date -d "$start_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$start_time" +%s 2>/dev/null)
            end_epoch=$(date -d "$end_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$end_time" +%s 2>/dev/null)

            if [[ -n "$start_epoch" && -n "$end_epoch" ]]; then
                runtime=$((end_epoch - start_epoch))
                total_runtime=$((total_runtime + runtime))
                runtime_count=$((runtime_count + 1))
            fi
        fi

        # Queue time
        submit_time=$(grep "^SUBMIT_TIME=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
        if [[ -n "$submit_time" && -n "$start_time" && "$submit_time" != "$start_time" ]]; then
            submit_epoch=$(date -d "$submit_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$submit_time" +%s 2>/dev/null)
            start_epoch=$(date -d "$start_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$start_time" +%s 2>/dev/null)

            if [[ -n "$submit_epoch" && -n "$start_epoch" && $start_epoch -gt $submit_epoch ]]; then
                queue_duration=$((start_epoch - submit_epoch))
                total_queue_time=$((total_queue_time + queue_duration))
                queue_count=$((queue_count + 1))
            fi
        fi
    fi
done

if [[ $runtime_count -gt 0 ]]; then
    avg_runtime=$((total_runtime / runtime_count))
    avg_minutes=$((avg_runtime / 60))
    avg_seconds=$((avg_runtime % 60))

    echo " Average Execution Time:"
    echo "  ${avg_minutes}m ${avg_seconds}s (across $runtime_count jobs)"
    echo ""
fi

if [[ $queue_count -gt 0 ]]; then
    avg_queue=$((total_queue_time / queue_count))
    avg_minutes=$((avg_queue / 60))
    avg_seconds=$((avg_queue % 60))

    echo " Average Queue Time:"
    echo "  ${avg_minutes}m ${avg_seconds}s (across $queue_count jobs)"
    echo ""
fi

# DISK USAGE

if command -v du &> /dev/null; then
    job_disk=$(du -sh "$JOB_DIR" 2>/dev/null | cut -f1)

    if [[ -d "$ARCHIVE_DIR" ]]; then
        archive_disk=$(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1)
    else
        archive_disk="0"
    fi

    echo " Disk Usage:"
    echo "  Active Jobs:  $job_disk"
    echo "  Archive:      $archive_disk"
    echo ""
fi

# RECOMMENDATIONS

echo "Recommendations:"

if [[ $failed_jobs -gt 5 ]]; then
    echo "  High failure rate detected. Review failed jobs with: $SCRIPT_NAME -list --status FAILED"
fi

if [[ $weight_percent -gt 90 ]]; then
    echo "  Near weight limit. Consider increasing MAX_TOTAL_WEIGHT or cleaning up jobs."
fi

if [[ $job_percent -gt 90 ]]; then
    echo "  Near job limit. Consider increasing MAX_CONCURRENT_JOBS or cleaning up jobs."
fi

if [[ $archived_jobs -gt 500 ]]; then
    echo "   Large archive. Consider cleaning old archives to save disk space."
fi

if [[ $total_jobs -eq 0 ]]; then
    echo "  No jobs found. Submit a job with: $SCRIPT_NAME -qrun <job_file>.run"
fi

if [[ $completed_jobs -gt 0 && $archived_jobs -eq 0 ]]; then
    echo "   Archive completed jobs to clean up: $SCRIPT_NAME -archive"
fi

echo ""
echo "========================================================"
echo "For detailed job info: $SCRIPT_NAME -list"
echo "For real-time monitoring: $SCRIPT_NAME -watch all"
