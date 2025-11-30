#!/bin/bash
# compare.mod - Job Comparison & Diff

JOB1="$1"
JOB2="$2"

if [[ -z "$JOB1" || -z "$JOB2" ]]; then
    echo "Job Comparison & Diff"
    echo "========================================================"
    echo ""
    echo "Usage: $SCRIPT_NAME -compare <job_id_1> <job_id_2>"
    echo ""
    echo "Compare two jobs side-by-side to understand differences in:"
    echo "  • Parameters (weight, GPU, priority)"
    echo "  • Execution times (queue, run duration)"
    echo "  • Exit status and results"
    echo "  • Commands and scripts"
    echo ""
    echo "Example:"
    echo "  $SCRIPT_NAME -compare job_001 job_002"
    exit 0
fi

# Validate job ID format
if [[ ! "$JOB1" =~ ^job_[0-9]{3}$ ]]; then
    error_msg "Invalid job ID format for first job: '$JOB1'. Expected: job_XXX"
    exit 1
fi

if [[ ! "$JOB2" =~ ^job_[0-9]{3}$ ]]; then
    error_msg "Invalid job ID format for second job: '$JOB2'. Expected: job_XXX"
    exit 1
fi

# Find jobs (check active and archive)
find_job() {
    local job_id="$1"
    local job_path=""

    # Check active jobs
    if [[ -d "$JOB_DIR/$job_id" ]]; then
        job_path="$JOB_DIR/$job_id"
    else
        # Check archives
        for archive_batch in "$ARCHIVE_DIR"/[0-9][0-9][0-9]; do
            if [[ -d "$archive_batch/$job_id" ]]; then
                job_path="$archive_batch/$job_id"
                break
            fi
        done
    fi

    echo "$job_path"
}

JOB1_PATH=$(find_job "$JOB1")
JOB2_PATH=$(find_job "$JOB2")

if [[ -z "$JOB1_PATH" ]]; then
    error_msg "Job '$JOB1' not found"
    exit 1
fi

if [[ -z "$JOB2_PATH" ]]; then
    error_msg "Job '$JOB2' not found"
    exit 1
fi

echo "Job Comparison: $JOB1 vs $JOB2"
echo "========================================================"
echo ""

# Read metadata for both jobs
read_job_info() {
    local job_path="$1"
    local field="$2"
    grep "^${field}=" "$job_path/job.info" 2>/dev/null | cut -d= -f2
}

# Job 1 metadata
J1_STATUS=$(read_job_info "$JOB1_PATH" "STATUS")
J1_NAME=$(read_job_info "$JOB1_PATH" "JOB_NAME")
J1_WEIGHT=$(read_job_info "$JOB1_PATH" "WEIGHT")
J1_GPU=$(read_job_info "$JOB1_PATH" "GPU")
J1_PRIORITY=$(read_job_info "$JOB1_PATH" "PRIORITY")
J1_SUBMIT=$(read_job_info "$JOB1_PATH" "SUBMIT_TIME")
J1_START=$(read_job_info "$JOB1_PATH" "START_TIME")
J1_END=$(read_job_info "$JOB1_PATH" "END_TIME")
J1_USER=$(read_job_info "$JOB1_PATH" "USER")

# Job 2 metadata
J2_STATUS=$(read_job_info "$JOB2_PATH" "STATUS")
J2_NAME=$(read_job_info "$JOB2_PATH" "JOB_NAME")
J2_WEIGHT=$(read_job_info "$JOB2_PATH" "WEIGHT")
J2_GPU=$(read_job_info "$JOB2_PATH" "GPU")
J2_PRIORITY=$(read_job_info "$JOB2_PATH" "PRIORITY")
J2_SUBMIT=$(read_job_info "$JOB2_PATH" "SUBMIT_TIME")
J2_START=$(read_job_info "$JOB2_PATH" "START_TIME")
J2_END=$(read_job_info "$JOB2_PATH" "END_TIME")
J2_USER=$(read_job_info "$JOB2_PATH" "USER")

# Compare function with highlighting
compare_field() {
    local label="$1"
    local val1="$2"
    local val2="$3"

    printf "%-20s │ %-25s │ %-25s" "$label" "$val1" "$val2"

    if [[ "$val1" != "$val2" ]]; then
        echo "  DIFFERENT"
    else
        echo "  [OK]"
    fi
}

# Display comparison table
echo "┌────────────────────┬───────────────────────────┬───────────────────────────┐"
echo "│ Field              │ $JOB1                 │ $JOB2                 │"
echo "├────────────────────┼───────────────────────────┼───────────────────────────┤"

compare_field "Status" "$J1_STATUS" "$J2_STATUS"
compare_field "Name" "$J1_NAME" "$J2_NAME"
compare_field "Weight" "$J1_WEIGHT" "$J2_WEIGHT"
compare_field "GPU" "$J1_GPU" "$J2_GPU"
compare_field "Priority" "$J1_PRIORITY" "$J2_PRIORITY"
compare_field "User" "$J1_USER" "$J2_USER"

echo "├────────────────────┼───────────────────────────┼───────────────────────────┤"

compare_field "Submit Time" "$J1_SUBMIT" "$J2_SUBMIT"
compare_field "Start Time" "$J1_START" "$J2_START"
compare_field "End Time" "$J1_END" "$J2_END"

echo "└────────────────────┴───────────────────────────┴───────────────────────────┘"
echo ""

# Calculate durations
calc_duration() {
    local start="$1"
    local end="$2"
    local start_epoch
    local end_epoch
    local duration
    local minutes
    local seconds

    if [[ -z "$start" || -z "$end" || "$start" == "N/A" || "$end" == "N/A" ]]; then
        echo "N/A"
        return
    fi

    start_epoch=$(date -d "$start" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$start" +%s 2>/dev/null)
    end_epoch=$(date -d "$end" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$end" +%s 2>/dev/null)

    if [[ -n "$start_epoch" && -n "$end_epoch" ]]; then
        duration=$((end_epoch - start_epoch))

        # Handle negative durations (clock skew or manual editing)
        if [[ $duration -lt 0 ]]; then
            echo "N/A (negative)"
            return
        fi

        minutes=$((duration / 60))
        seconds=$((duration % 60))
        echo "${minutes}m ${seconds}s"
    else
        echo "N/A"
    fi
}

J1_DURATION=$(calc_duration "$J1_START" "$J1_END")
J2_DURATION=$(calc_duration "$J2_START" "$J2_END")

echo " Execution Time Comparison:"
echo "  $JOB1: $J1_DURATION"
echo "  $JOB2: $J2_DURATION"
echo ""

# Compare commands if available
if [[ -f "$JOB1_PATH/command.run" && -f "$JOB2_PATH/command.run" ]]; then
    echo " Command Comparison:"
    echo ""

    # Check if commands are identical
    if diff -q "$JOB1_PATH/command.run" "$JOB2_PATH/command.run" &>/dev/null; then
        echo "Commands are identical"
    else
        echo "Commands differ:"
        echo ""
        echo "────────── $JOB1 ──────────"
        head -10 "$JOB1_PATH/command.run"
        echo ""
        echo "────────── $JOB2 ──────────"
        head -10 "$JOB2_PATH/command.run"
        echo ""

        # Show diff if command -v diff is available
        if command -v diff &>/dev/null; then
            echo "Differences:"
            diff -u "$JOB1_PATH/command.run" "$JOB2_PATH/command.run" | head -20
        fi
    fi
    echo ""
fi

# Exit code comparison
if [[ -f "$JOB1_PATH/exit_code" && -f "$JOB2_PATH/exit_code" ]]; then
    J1_EXIT=$(cat "$JOB1_PATH/exit_code" 2>/dev/null)
    J2_EXIT=$(cat "$JOB2_PATH/exit_code" 2>/dev/null)

    echo "Exit Code Comparison:"
    echo "  $JOB1: $J1_EXIT"
    echo "  $JOB2: $J2_EXIT"

    if [[ "$J1_EXIT" == "$J2_EXIT" ]]; then
        echo "  Same exit code"
    else
        echo "  Different exit codes"
    fi
    echo ""
fi

# Summary
echo "========================================================"
echo "Summary:"

if [[ "$J1_STATUS" == "COMPLETED" && "$J2_STATUS" == "COMPLETED" ]]; then
    echo "  Both jobs completed successfully"
elif [[ "$J1_STATUS" == "FAILED" && "$J2_STATUS" == "FAILED" ]]; then
    echo "  Both jobs failed"
elif [[ "$J1_STATUS" == "COMPLETED" && "$J2_STATUS" == "FAILED" ]]; then
    echo "  $JOB1 succeeded but $JOB2 failed"
    echo "     Compare logs to debug: $SCRIPT_NAME -logs $JOB2"
elif [[ "$J1_STATUS" == "FAILED" && "$J2_STATUS" == "COMPLETED" ]]; then
    echo "  $JOB2 succeeded but $JOB1 failed"
    echo "     Compare logs to debug: $SCRIPT_NAME -logs $JOB1"
fi
