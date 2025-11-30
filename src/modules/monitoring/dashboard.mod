#!/bin/bash
# dashboard.mod - Real-Time Dashboard

# Get refresh interval
REFRESH_INTERVAL="${WATCH_REFRESH_INTERVAL:-3}"

# Validate refresh interval is a positive integer
if [[ ! "$REFRESH_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$REFRESH_INTERVAL" -lt 1 ]]; then
    echo "ERROR: Invalid WATCH_REFRESH_INTERVAL: '$REFRESH_INTERVAL'"
    echo "Must be a positive integer. Using default: 3"
    REFRESH_INTERVAL=3
fi

echo "Starting Real-Time Dashboard (refresh: ${REFRESH_INTERVAL}s)..."
echo "Press Ctrl+C to exit"
sleep 1

while true; do
    # Clear screen
    clear

    # Header
    echo "==============================================================================="
    echo "                    JOB SCHEDULER - REAL-TIME DASHBOARD"
    echo "==============================================================================="
    echo "  Updated: $(date '+%Y-%m-%d %H:%M:%S')                     Refresh: ${REFRESH_INTERVAL}s"
    echo "==============================================================================="
    echo ""

    # Calculate resource usage
    total_weight=0
    running_count=0
    queued_count=0
    paused_count=0
    completed_count=0
    failed_count=0

    for job_dir in "$JOB_DIR"/job_*; do
        [[ ! -d "$job_dir" ]] && continue
        [[ ! -f "$job_dir/job.info" ]] && continue

        status=$(grep "^STATUS=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)

        case "$status" in
            RUNNING)
                running_count=$((running_count + 1))
                # Check if actually running
                if [[ -f "$job_dir/job.pid" ]]; then
                    pid=$(cat "$job_dir/job.pid" 2>/dev/null)
                    if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
                        weight=$(grep "^WEIGHT=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
                        [[ -n "$weight" && "$weight" =~ ^[0-9]+$ ]] && total_weight=$((total_weight + weight))
                    fi
                fi
                ;;
            QUEUED) queued_count=$((queued_count + 1)) ;;
            PAUSED) paused_count=$((paused_count + 1)) ;;
            COMPLETED) completed_count=$((completed_count + 1)) ;;
            FAILED) failed_count=$((failed_count + 1)) ;;
        esac
    done

    # Resource utilization
    weight_percent=0
    job_percent=0

    [[ "$MAX_TOTAL_WEIGHT" -gt 0 ]] && weight_percent=$((total_weight * 100 / MAX_TOTAL_WEIGHT))
    [[ "$MAX_CONCURRENT_JOBS" -gt 0 ]] && job_percent=$((running_count * 100 / MAX_CONCURRENT_JOBS))

    # Display resource bars
    echo "┌─ RESOURCE UTILIZATION ─────────────────────────────────────────────────────┐"
    echo "│"

    # Weight bar
    printf "│  Weight: %3d / %3d (%3d%%) [" "$total_weight" "$MAX_TOTAL_WEIGHT" "$weight_percent"
    bar_length=$((weight_percent / 2))
    for ((i=0; i<50; i++)); do
        if [[ $i -lt $bar_length ]]; then
            printf "#"
        else
            printf "-"
        fi
    done
    printf "]\n"

    # Job slots bar
    printf "│  Jobs:   %3d / %3d (%3d%%) [" "$running_count" "$MAX_CONCURRENT_JOBS" "$job_percent"
    bar_length=$((job_percent / 2))
    for ((i=0; i<50; i++)); do
        if [[ $i -lt $bar_length ]]; then
            printf "#"
        else
            printf "-"
        fi
    done
    printf "]\n"
    echo "│"
    echo "└────────────────────────────────────────────────────────────────────────────┘"
    echo ""

    # Job counts
    echo "┌─ JOB STATUS SUMMARY ───────────────────────────────────────────────────────┐"
    printf "│  Running:   %-3d     Queued:  %-3d     Paused: %-3d\n" "$running_count" "$queued_count" "$paused_count"
    printf "│  Completed: %-3d    Failed:  %-3d\n" "$completed_count" "$failed_count"
    echo "└────────────────────────────────────────────────────────────────────────────┘"
    echo ""

    # Running jobs details
    if [[ $running_count -gt 0 ]]; then
        echo "┌─ RUNNING JOBS ─────────────────────────────────────────────────────────────┐"
        for job_dir in "$JOB_DIR"/job_*; do
            [[ ! -d "$job_dir" ]] && continue
            [[ ! -f "$job_dir/job.info" ]] && continue

            status=$(grep "^STATUS=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
            [[ "$status" != "RUNNING" ]] && continue

            job_id=$(basename "$job_dir")
            job_name=$(grep "^JOB_NAME=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
            priority=$(grep "^PRIORITY=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
            weight=$(grep "^WEIGHT=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
            start_time=$(grep "^START_TIME=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)

            # Calculate runtime
            if [[ -n "$start_time" && "$start_time" != "N/A" ]]; then
                start_epoch=$(date -d "$start_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$start_time" +%s 2>/dev/null)
                now_epoch=$(date +%s)
                if [[ -n "$start_epoch" ]]; then
                    runtime=$((now_epoch - start_epoch))
                    runtime_str="$((runtime / 60))m $((runtime % 60))s"
                else
                    runtime_str="N/A"
                fi
            else
                runtime_str="N/A"
            fi

            # Priority icon
            case "$priority" in
                urgent) p_icon="" ;;
                high) p_icon="" ;;
                low) p_icon="" ;;
                *) p_icon="" ;;
            esac

            # Display job
            display_name="$job_id"
            [[ -n "$job_name" && "$job_name" != "N/A" ]] && display_name="$job_id ($job_name)"
            printf "│  %s %-40s W:%-3s  Runtime: %s\n" "$p_icon" "${display_name:0:40}" "$weight" "$runtime_str"
        done
        echo "└────────────────────────────────────────────────────────────────────────────┘"
        echo ""
    fi

    # Queued jobs
    if [[ $queued_count -gt 0 ]]; then
        echo "┌─ QUEUED JOBS ──────────────────────────────────────────────────────────────┐"
        queue_shown=0
        for queued in "$QUEUE_DIR"/*.run; do
            [[ ! -f "$queued" ]] && continue
            [[ $queue_shown -ge 5 ]] && break

            job_name=$(basename "$queued" .run)
            weight_file="${queued%.run}.weight"
            priority_file="${queued%.run}.priority"

            weight=$(cat "$weight_file" 2>/dev/null || echo "N/A")
            priority=$(cat "$priority_file" 2>/dev/null || echo "normal")

            case "$priority" in
                urgent) p_icon="" ;;
                high) p_icon="" ;;
                low) p_icon="" ;;
                *) p_icon="" ;;
            esac

            printf "│  %s %-50s W:%-3s\n" "$p_icon" "$job_name" "$weight"
            queue_shown=$((queue_shown + 1))
        done

        [[ $queued_count -gt 5 ]] && echo "│  ... and $((queued_count - 5)) more queued jobs"
        echo "└────────────────────────────────────────────────────────────────────────────┘"
        echo ""
    fi

    echo "==============================================================================="
    echo "  Commands: -list | -status | -stats | -visual | Ctrl+C to exit"
    echo "==============================================================================="

    # Wait for next refresh
    sleep "$REFRESH_INTERVAL"
done
