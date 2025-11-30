#!/bin/bash
# watch.mod - Real-time job monitoring
# Uses concurrency-safe operations from common.mod
# ALL BUGS FIXED - Version 3.0

WATCH_TARGET="$1"

if [[ -z "$WATCH_TARGET" ]]; then
    error_msg "Specify a job ID or 'all' (e.g., $SCRIPT_NAME -watch job_001)"
    exit 1
fi

# Trap Ctrl+C to exit cleanly
trap 'echo ""; echo "Exiting watch mode..."; exit 0' INT

while true; do
    clear
    echo "Monitoring jobs (Updated: $(date '+%Y-%m-%d %H:%M:%S'))"
    echo "Press Ctrl+C to exit"
    echo ""

    if [[ "$WATCH_TARGET" == "all" ]]; then
        # Show all running jobs
        echo "Running Jobs:"
        running_count=0

        # Handle empty glob expansion
        for folder in "$JOB_DIR"/job_*; do
            [[ ! -d "$folder" ]] && continue

            if [[ -f "$folder/job.pid" ]]; then
                JOB_PID=$(cat "$folder/job.pid" 2>/dev/null)

                if [[ -n "$JOB_PID" ]] && ps -p "$JOB_PID" > /dev/null 2>&1; then
                    running_count=$((running_count + 1))
                    job_name=$(basename "$folder")

                    # Read job info
                    weight="N/A"
                    gpu="N/A"
                    user="N/A"

                    if [[ -f "$folder/job.info" ]]; then
                        # Use head -1 to get first match only
                        weight=$(grep "^WEIGHT=" "$folder/job.info" | head -1 | cut -d= -f2)
                        gpu=$(grep "^GPU=" "$folder/job.info" | head -1 | cut -d= -f2)
                        user=$(grep "^USER=" "$folder/job.info" | head -1 | cut -d= -f2)
                        start_time=$(grep "^START_TIME=" "$folder/job.info" | head -1 | cut -d= -f2)

                        # Calculate duration
                        duration="N/A"
                        if [[ -n "$start_time" ]]; then
                            duration=$(calculate_run_duration "$start_time")
                        fi
                    fi

                    echo "  $job_name (PID: $JOB_PID, User: $user, Duration: $duration, Weight: $weight, GPU: $gpu)"

                    # Show last few lines of log
                    log_file=$(ls "$folder"/*.log 2>/dev/null | head -1)
                    if [[ -f "$log_file" ]]; then
                        last_line=$(tail -n 1 "$log_file" 2>/dev/null | head -c 80)
                        [[ -n "$last_line" ]] && echo "     Last output: $last_line"
                    fi
                fi
            fi
        done

        [[ "$running_count" -eq 0 ]] && echo "  (none)"
        echo ""

        echo "Queued Jobs:"
        queued_count=0

        # Handle empty glob expansion
        for queued in "$QUEUE_DIR"/*.run; do
            [[ ! -f "$queued" ]] && continue

            queued_count=$((queued_count + 1))
            job_name=$(basename "$queued" .run)

            # Get user from job directory if it exists
            user="N/A"
            if [[ -f "$JOB_DIR/$job_name/job.info" ]]; then
                user=$(grep "^USER=" "$JOB_DIR/$job_name/job.info" | head -1 | cut -d= -f2)
            fi

            echo "   $job_name (User: $user)"
        done

        [[ "$queued_count" -eq 0 ]] && echo "  (none)"
        echo ""

        # Show resource summary
        read running_jobs total_weight <<< "$(calculate_resource_usage)"
        echo "Resources: $running_jobs/$MAX_CONCURRENT_JOBS jobs, Weight: $total_weight/$MAX_TOTAL_WEIGHT"

    else
        # Show specific job
        JOB_PATH="$JOB_DIR/$WATCH_TARGET"
        if [[ ! -d "$JOB_PATH" ]]; then
            # Use error_msg
            error_msg "Job '$WATCH_TARGET' not found!"
            sleep "$WATCH_REFRESH_INTERVAL"
            continue
        fi

        echo "Job: $WATCH_TARGET"
        echo "----------------------------------------"

        # Show job info
        if [[ -f "$JOB_PATH/job.info" ]]; then
            cat "$JOB_PATH/job.info" | sed 's/^/  /'
        fi
        echo ""

        # Show job status
        if [[ -f "$JOB_PATH/job.pid" ]]; then
            JOB_PID=$(cat "$JOB_PATH/job.pid" 2>/dev/null)
            if [[ -n "$JOB_PID" ]] && ps -p "$JOB_PID" > /dev/null 2>&1; then
                echo "Status: RUNNING (PID: $JOB_PID)"
            else
                echo "Status: NOT RUNNING (stale PID file)"
            fi
        else
            status="COMPLETED"
            [[ -f "$JOB_PATH/job.info" ]] && status=$(grep "^STATUS=" "$JOB_PATH/job.info" | head -1 | cut -d= -f2)

            if [[ "$status" == "COMPLETED" ]]; then
                echo "Status: COMPLETED"
            elif [[ "$status" == "KILLED" ]]; then
                echo "Status:  KILLED"
            elif [[ "$status" == "FAILED" ]]; then
                echo "Status: FAILED"
            else
                echo "Status: $status"
            fi

            [[ -f "$JOB_PATH/exit.code" ]] && echo "Exit Code: $(cat "$JOB_PATH/exit.code" 2>/dev/null)"
        fi
        echo ""

        # Show log tail
        log_file=$(ls "$JOB_PATH"/*.log 2>/dev/null | head -1)
        if [[ -f "$log_file" ]]; then
            echo "Log Output (last 20 lines):"
            echo "----------------------------------------"
            tail -n 20 "$log_file" 2>/dev/null
        else
            echo "No log file found"
        fi
    fi

    sleep "$WATCH_REFRESH_INTERVAL"
done
