#!/bin/bash
# visual.mod - Visual Workflows & Gantt Charts
# ASCII visualization of job execution timelines

echo "Visual Workflow - Job Timeline"
echo "========================================================"
echo ""

# COLLECT JOB DATA

declare -a job_data=()
earliest_time=9999999999
latest_time=0

for job_dir in "$JOB_DIR"/job_*; do
    [[ ! -d "$job_dir" ]] && continue
    [[ ! -f "$job_dir/job.info" ]] && continue

    job_id=$(basename "$job_dir")
    status=$(grep "^STATUS=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
    submit_time=$(grep "^SUBMIT_TIME=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
    start_time=$(grep "^START_TIME=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
    end_time=$(grep "^END_TIME=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
    job_name=$(grep "^JOB_NAME=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
    priority=$(grep "^PRIORITY=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)

    # Skip if no timing info
    [[ -z "$submit_time" ]] && continue

    # Convert to epoch
    submit_epoch=$(date -d "$submit_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$submit_time" +%s 2>/dev/null)
    [[ -z "$submit_epoch" ]] && continue

    start_epoch="$submit_epoch"
    if [[ -n "$start_time" && "$start_time" != "N/A" ]]; then
        start_epoch=$(date -d "$start_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$start_time" +%s 2>/dev/null)
        [[ -z "$start_epoch" ]] && start_epoch="$submit_epoch"
    fi

    end_epoch="$start_epoch"
    if [[ -n "$end_time" && "$end_time" != "N/A" ]]; then
        end_epoch=$(date -d "$end_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$end_time" +%s 2>/dev/null)
        [[ -z "$end_epoch" ]] && end_epoch=$(date +%s)
    elif [[ "$status" == "RUNNING" ]]; then
        end_epoch=$(date +%s)
    fi

    # Track time range
    [[ $submit_epoch -lt $earliest_time ]] && earliest_time=$submit_epoch
    [[ $end_epoch -gt $latest_time ]] && latest_time=$end_epoch

    # Store: "job_id|status|submit|start|end|name|priority"
    job_data+=("$job_id|$status|$submit_epoch|$start_epoch|$end_epoch|$job_name|$priority")
done

# Check if we have data
if [[ ${#job_data[@]} -eq 0 ]]; then
    echo "No jobs with timing data found."
    echo ""
    echo "Submit jobs to see visual workflow:"
    echo "  $SCRIPT_NAME -qrun <job_file>.run"
    exit 0
fi

# CALCULATE TIMELINE SCALE

total_duration=$((latest_time - earliest_time))
[[ $total_duration -eq 0 ]] && total_duration=1

# Timeline width (in characters)
timeline_width=60

# RENDER GANTT CHART

echo "Timeline: $(date -d @$earliest_time "+%H:%M:%S" 2>/dev/null || date -r $earliest_time "+%H:%M:%S" 2>/dev/null) to $(date -d @$latest_time "+%H:%M:%S" 2>/dev/null || date -r $latest_time "+%H:%M:%S" 2>/dev/null)"
echo "Duration: $((total_duration / 60))m $((total_duration % 60))s"
echo ""

# Sort jobs by submit time
sorted_jobs=$(printf '%s\n' "${job_data[@]}" | sort -t'|' -k3 -n)

while IFS='|' read -r job_id status submit_epoch start_epoch end_epoch job_name priority; do
    # Calculate positions
    submit_pos=$(( (submit_epoch - earliest_time) * timeline_width / total_duration ))
    start_pos=$(( (start_epoch - earliest_time) * timeline_width / total_duration ))
    end_pos=$(( (end_epoch - earliest_time) * timeline_width / total_duration ))

    # Ensure minimum widths
    [[ $start_pos -lt 0 ]] && start_pos=0
    [[ $end_pos -gt $timeline_width ]] && end_pos=$timeline_width
    [[ $end_pos -le $start_pos ]] && end_pos=$((start_pos + 1))

    # Choose characters based on status
    case "$status" in
        RUNNING)    queue_char="."; run_char="#"; color_code="" ;;
        COMPLETED)  queue_char="."; run_char="="; color_code="" ;;
        FAILED)     queue_char="."; run_char="-"; color_code="" ;;
        KILLED)     queue_char="."; run_char="X"; color_code="" ;;
        QUEUED)     queue_char="."; run_char="."; color_code="" ;;
        *)          queue_char="."; run_char="─"; color_code="" ;;
    esac

    # Priority indicator
    case "$priority" in
        urgent) priority_icon="" ;;
        high)   priority_icon="" ;;
        low)    priority_icon="" ;;
        *)      priority_icon="" ;;
    esac

    # Build timeline
    timeline=""

    # Queue phase (submit to start)
    for ((i=0; i<submit_pos; i++)); do
        timeline+=" "
    done

    queue_length=$((start_pos - submit_pos))
    for ((i=0; i<queue_length; i++)); do
        timeline+="$queue_char"
    done

    # Run phase (start to end)
    run_length=$((end_pos - start_pos))
    for ((i=0; i<run_length; i++)); do
        timeline+="$run_char"
    done

    # Pad remaining
    remaining=$((timeline_width - end_pos))
    for ((i=0; i<remaining; i++)); do
        timeline+=" "
    done

    # Display name
    display_name="$job_id"
    if [[ -n "$job_name" && "$job_name" != "N/A" ]]; then
        display_name="$job_id ($job_name)"
    fi

    # Truncate if too long
    if [[ ${#display_name} -gt 20 ]]; then
        display_name="${display_name:0:17}..."
    fi

    # Print timeline
    printf "%-22s %s |%s| %s\n" "$display_name" "$priority_icon" "$timeline" "$status"

done <<< "$sorted_jobs"

echo ""

# LEGEND

echo "Legend:"
echo "  # Running    = Completed    - Failed    X Killed    . Queued"
echo "   Urgent     High         Normal     Low"
echo ""

# SUMMARY STATISTICS

echo "Summary:"

# Count by status
running_count=$(printf '%s\n' "${job_data[@]}" | grep -c "|RUNNING|")
completed_count=$(printf '%s\n' "${job_data[@]}" | grep -c "|COMPLETED|")
failed_count=$(printf '%s\n' "${job_data[@]}" | grep -c "|FAILED|")
queued_count=$(printf '%s\n' "${job_data[@]}" | grep -c "|QUEUED|")

echo "  Running:   $running_count"
echo "  Completed: $completed_count"
echo "  Failed:    $failed_count"
echo "  Queued:    $queued_count"
echo ""

echo "========================================================"
echo "Tip: Use -watch all for real-time monitoring"
echo "     Use -stats for detailed analytics"
