#!/bin/bash
# list.mod - List all jobs (running, queued, completed)
# Uses concurrency-safe operations from common.mod
# ALL BUGS FIXED - Version 3.0

echo "Listing all jobs..."
echo ""

echo "Running Jobs:"
running_count=0

# Handle empty glob expansion
for folder in "$JOB_DIR"/job_*; do
    [[ ! -d "$folder" ]] && continue

    if [[ -f "$folder/job.pid" ]]; then
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
        fi

        # Calculate total duration (submit to now)
        duration="N/A"
        if [[ "$submit_time" != "N/A" ]]; then
            duration=$(calculate_total_duration "$submit_time")
        elif [[ "$start_time" != "N/A" ]]; then
            # Fallback for old jobs without SUBMIT_TIME
            duration=$(calculate_run_duration "$start_time")
        fi

        # Display with friendly name if provided
        if [[ -n "$friendly_name" ]]; then
            echo "  $job_name [$friendly_name] - User: $user, Duration: $duration (Weight: $weight, GPU: $gpu)"
        else
            echo "  $job_name - User: $user, Duration: $duration (Weight: $weight, GPU: $gpu)"
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

    # Get weight from metadata file
    weight_file="${queued%.run}.weight"
    if [[ -f "$weight_file" ]]; then
        weight=$(cat "$weight_file" 2>/dev/null)
        [[ ! "$weight" =~ ^[0-9]+$ ]] && weight="${DEFAULT_JOB_WEIGHT:-10}"
    else
        weight="${DEFAULT_JOB_WEIGHT:-10}"
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

    echo "   $job_name - User: $user (Weight: $weight, GPU: $gpu)"
done

[[ "$queued_count" -eq 0 ]] && echo "  (none)"
echo ""

echo "Completed Jobs:"
completed_count=0

# Handle empty glob expansion
for folder in "$JOB_DIR"/job_*; do
    [[ ! -d "$folder" ]] && continue

    if [[ ! -f "$folder/job.pid" ]]; then
        completed_count=$((completed_count + 1))
        job_name=$(basename "$folder")

        # Read job info
        status="COMPLETED"
        user="N/A"
        exit_code="N/A"
        submit_time="N/A"
        start_time="N/A"
        end_time="N/A"
        friendly_name=""

        if [[ -f "$folder/job.info" ]]; then
            # Use head -1 to get first match only
            status=$(grep "^STATUS=" "$folder/job.info" | head -1 | cut -d= -f2)
            user=$(grep "^USER=" "$folder/job.info" | head -1 | cut -d= -f2)
            submit_time=$(grep "^SUBMIT_TIME=" "$folder/job.info" | head -1 | cut -d= -f2)
            start_time=$(grep "^START_TIME=" "$folder/job.info" | head -1 | cut -d= -f2)
            end_time=$(grep "^END_TIME=" "$folder/job.info" | head -1 | cut -d= -f2)
            friendly_name=$(grep "^JOB_NAME=" "$folder/job.info" | head -1 | cut -d= -f2)
        fi

        [[ -f "$folder/exit.code" ]] && exit_code=$(cat "$folder/exit.code" 2>/dev/null)

        # Calculate total duration
        duration="N/A"
        if [[ "$submit_time" != "N/A" && "$end_time" != "N/A" ]]; then
            duration=$(calculate_total_duration "$submit_time" "$end_time")
        elif [[ "$start_time" != "N/A" && "$end_time" != "N/A" ]]; then
            # Fallback for old jobs without SUBMIT_TIME
            duration=$(calculate_run_duration "$start_time" "$end_time")
        fi

        # Display with friendly name if provided
        if [[ -n "$friendly_name" ]]; then
            if [[ "$status" == "COMPLETED" ]]; then
                echo "  $job_name [$friendly_name] - User: $user, Duration: $duration (Exit: $exit_code)"
            elif [[ "$status" == "KILLED" ]]; then
                echo "   $job_name [$friendly_name] - User: $user, Duration: $duration (KILLED)"
            else
                echo "  $job_name [$friendly_name] - User: $user, Duration: $duration (Exit: $exit_code, Status: $status)"
            fi
        else
            if [[ "$status" == "COMPLETED" ]]; then
                echo "  $job_name - User: $user, Duration: $duration (Exit: $exit_code)"
            elif [[ "$status" == "KILLED" ]]; then
                echo "   $job_name - User: $user, Duration: $duration (KILLED)"
            else
                echo "  $job_name - User: $user, Duration: $duration (Exit: $exit_code, Status: $status)"
            fi
        fi
    fi
done

[[ "$completed_count" -eq 0 ]] && echo "  (none)"
echo ""

echo "Summary: $running_count running, $queued_count queued, $completed_count completed"
