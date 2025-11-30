#!/bin/bash
# status.mod - Display current job status
# Uses concurrency-safe operations from common.mod
# ALL BUGS FIXED - Version 3.0

# Calculate running totals
running_count=0
total_weight=0

echo "Checking job status..."
echo ""
echo "Running Jobs:"

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
            submit_time="N/A"
            queue_time="N/A"
            start_time="N/A"
            friendly_name=""

            if [[ -f "$folder/job.info" ]]; then
                # Use head -1 to get first match only
                weight=$(grep "^WEIGHT=" "$folder/job.info" | head -1 | cut -d= -f2)
                gpu=$(grep "^GPU=" "$folder/job.info" | head -1 | cut -d= -f2)
                user=$(grep "^USER=" "$folder/job.info" | head -1 | cut -d= -f2)
                submit_time=$(grep "^SUBMIT_TIME=" "$folder/job.info" | head -1 | cut -d= -f2)
                queue_time=$(grep "^QUEUE_TIME=" "$folder/job.info" | head -1 | cut -d= -f2)
                start_time=$(grep "^START_TIME=" "$folder/job.info" | head -1 | cut -d= -f2)
                friendly_name=$(grep "^JOB_NAME=" "$folder/job.info" | head -1 | cut -d= -f2)

                # Validate weight is numeric before arithmetic
                if [[ -n "$weight" && "$weight" =~ ^[0-9]+$ ]]; then
                    total_weight=$((total_weight + weight))
                else
                    weight="N/A"
                fi
            fi

            # Calculate durations (queue vs run)
            duration_display=""
            if [[ "$queue_time" != "N/A" && "$queue_time" != "" ]]; then
                # Job was queued - show queue time + run time
                queue_dur=$(calculate_queue_duration "$submit_time" "$queue_time")
                run_dur=$(calculate_run_duration "$start_time")
                duration_display="Queue: $queue_dur, Run: $run_dur"
            elif [[ "$start_time" != "N/A" ]]; then
                # Immediate job - show run time only
                run_dur=$(calculate_run_duration "$start_time")
                duration_display="$run_dur"
            else
                duration_display="N/A"
            fi

            # Display friendly name if provided
            if [[ -n "$friendly_name" ]]; then
                echo "  $job_name [$friendly_name] (PID: $JOB_PID, User: $user, Duration: $duration_display, Weight: $weight, GPU: $gpu)"
            else
                echo "  $job_name (PID: $JOB_PID, User: $user, Duration: $duration_display, Weight: $weight, GPU: $gpu)"
            fi
        else
            # Stale PID file, clean up
            rm -f "$folder/job.pid"
        fi
    fi
done

[[ "$running_count" -eq 0 ]] && echo "  (none)"
echo ""
echo "Total Running: $running_count/$MAX_CONCURRENT_JOBS jobs, Weight: $total_weight/$MAX_TOTAL_WEIGHT"
echo ""

# Queued jobs
queued_count=0
queued_weight=0
echo "Queued Jobs:"

# Handle empty glob expansion
for queued in "$QUEUE_DIR"/*.run; do
    [[ ! -f "$queued" ]] && continue

    queued_count=$((queued_count + 1))
    job_name=$(basename "$queued" .run)

    # Get weight from metadata file
    weight_file="${queued%.run}.weight"
    if [[ -f "$weight_file" ]]; then
        weight=$(cat "$weight_file" 2>/dev/null)

        # Validate weight is numeric before arithmetic
        if [[ "$weight" =~ ^[0-9]+$ ]]; then
            queued_weight=$((queued_weight + weight))
        else
            weight="${DEFAULT_JOB_WEIGHT:-10}"
            queued_weight=$((queued_weight + weight))
        fi
    else
        weight="${DEFAULT_JOB_WEIGHT:-10}"
        queued_weight=$((queued_weight + weight))
    fi

    # Get GPU from metadata file
    gpu_file="${queued%.run}.gpu"
    if [[ -f "$gpu_file" ]]; then
        gpu=$(cat "$gpu_file" 2>/dev/null)
        [[ -z "$gpu" ]] && gpu="N/A"
    else
        gpu="N/A"
    fi

    # Get user from job directory if it exists
    user="N/A"
    if [[ -f "$JOB_DIR/$job_name/job.info" ]]; then
        user=$(grep "^USER=" "$JOB_DIR/$job_name/job.info" | head -1 | cut -d= -f2)
    fi

    # Get queue reason if available
    reason_file="${queued%.run}.reason"
    queue_reason=""
    if [[ -f "$reason_file" ]]; then
        queue_reason=$(cat "$reason_file" 2>/dev/null)
    fi

    # Get friendly name if available
    name_file="${queued%.run}.name"
    friendly_name=""
    if [[ -f "$name_file" ]]; then
        friendly_name=$(cat "$name_file" 2>/dev/null)
    fi

    # Display with friendly name if provided
    if [[ -n "$friendly_name" ]]; then
        echo "   $job_name [$friendly_name] (User: $user, Weight: $weight, GPU: $gpu)"
    else
        echo "   $job_name (User: $user, Weight: $weight, GPU: $gpu)"
    fi
    if [[ -n "$queue_reason" ]]; then
        echo "     ❗ Queued: $queue_reason"
    fi
done

[[ "$queued_count" -eq 0 ]] && echo "  (none)"
echo ""
echo "Total Queued: $queued_count jobs, Weight: $queued_weight"
echo ""

# Show GPU status if available
if has_gpu_support; then
    gpu_count=$(get_gpu_count)
    if [[ "$gpu_count" -gt 0 ]]; then
        echo "🎮 GPU Status:"
        allocated=$(get_allocated_gpus)
        if [[ -z "$allocated" ]]; then
            echo "  All $gpu_count GPU(s) available"
        else
            echo "  Total GPUs: $gpu_count"
            echo "  In use: $allocated"
        fi
        echo ""
    fi
fi
