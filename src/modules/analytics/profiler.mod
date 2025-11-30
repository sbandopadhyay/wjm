#!/bin/bash
# profiler.mod - Performance Profiler
# Monitors resource usage for a running job

JOB_ID="$1"

if [[ -z "$JOB_ID" ]]; then
    echo "Performance Profiler"
    echo "========================================================"
    echo ""
    echo "Monitor CPU, memory, and disk usage for a running job."
    echo ""
    echo "Usage: $SCRIPT_NAME -profile <job_id>"
    echo ""
    echo "Example:"
    echo "  $SCRIPT_NAME -profile job_001"
    exit 0
fi

# Check job exists
JOB_PATH="$JOB_DIR/$JOB_ID"
if [[ ! -d "$JOB_PATH" ]]; then
    error_msg "Job '$JOB_ID' not found"
    exit 1
fi

# Check job is running
if [[ ! -f "$JOB_PATH/job.pid" ]]; then
    error_msg "Job '$JOB_ID' is not running"
    exit 1
fi

PID=$(cat "$JOB_PATH/job.pid" 2>/dev/null)
if [[ -z "$PID" ]] || ! ps -p "$PID" >/dev/null 2>&1; then
    error_msg "Job '$JOB_ID' process not found (PID: $PID)"
    exit 1
fi

echo "Performance Profile: $JOB_ID (PID: $PID)"
echo "========================================================"
echo ""

# Get job info
JOB_NAME=$(grep "^JOB_NAME=" "$JOB_PATH/job.info" 2>/dev/null | cut -d= -f2)
START_TIME=$(grep "^START_TIME=" "$JOB_PATH/job.info" 2>/dev/null | cut -d= -f2)

[[ -n "$JOB_NAME" && "$JOB_NAME" != "N/A" ]] && echo "Job Name: $JOB_NAME"
echo "Start Time: $START_TIME"
echo ""

# Calculate runtime
if [[ -n "$START_TIME" && "$START_TIME" != "N/A" ]]; then
    start_epoch=$(date -d "$START_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$START_TIME" +%s 2>/dev/null)
    now_epoch=$(date +%s)
    if [[ -n "$start_epoch" ]]; then
        runtime=$((now_epoch - start_epoch))
        echo "Runtime: $((runtime / 60))m $((runtime % 60))s"
        echo ""
    fi
fi

# Collect resource samples
echo "Collecting performance samples (10 samples, 1 second apart)..."
echo ""

SAMPLES=10
cpu_total=0
mem_total=0
max_cpu=0
max_mem=0
min_cpu=999999
min_mem=999999
successful_samples=0
process_died=0

# Header
printf "%-8s %-10s %-10s %-10s\n" "Sample" "CPU %" "Memory %" "Mem (MB)"
echo "────────────────────────────────────────────"

for ((i=1; i<=SAMPLES; i++)); do
    # Get CPU and memory usage
    if command -v ps >/dev/null 2>&1; then
        # Linux/macOS compatible ps command
        stats=$(ps -p "$PID" -o %cpu=,%mem=,rss= 2>/dev/null)

        if [[ -n "$stats" ]]; then
            cpu=$(echo "$stats" | awk '{print $1}')
            mem=$(echo "$stats" | awk '{print $2}')
            rss=$(echo "$stats" | awk '{print $3}')  # RSS in KB

            # Validate rss is numeric before division
            if [[ ! "$rss" =~ ^[0-9]+$ ]]; then
                printf "%-8d %-10s %-10s %-10s\n" "$i" "N/A" "N/A" "N/A"
                continue
            fi

            # Convert to integers for comparison
            cpu_int=$(printf "%.0f" "$cpu" 2>/dev/null || echo "0")
            mem_int=$(printf "%.0f" "$mem" 2>/dev/null || echo "0")

            # Track min/max
            [[ $cpu_int -gt $max_cpu ]] && max_cpu=$cpu_int
            [[ $cpu_int -lt $min_cpu ]] && min_cpu=$cpu_int
            [[ $mem_int -gt $max_mem ]] && max_mem=$mem_int
            [[ $mem_int -lt $min_mem ]] && min_mem=$mem_int

            # Add to totals
            cpu_total=$((cpu_total + cpu_int))
            mem_total=$((mem_total + mem_int))
            successful_samples=$((successful_samples + 1))

            # Convert RSS to MB
            mem_mb=$((rss / 1024))

            printf "%-8d %-10s %-10s %-10s\n" "$i" "${cpu}%" "${mem}%" "${mem_mb}MB"
        else
            # Process died or ps failed
            printf "%-8d %-10s %-10s %-10s\n" "$i" "N/A" "N/A" "N/A"
            if [[ $i -lt $SAMPLES ]]; then
                process_died=1
            fi
        fi
    fi

    # Wait before next sample (except last one)
    [[ $i -lt $SAMPLES ]] && sleep 1
done

echo "────────────────────────────────────────────"
echo ""

# Warn if process died
if [[ $process_died -eq 1 ]]; then
    echo "Process died during sampling"
    echo ""
fi

# Calculate averages (divide by successful samples, not total)
if [[ $successful_samples -gt 0 ]]; then
    avg_cpu=$((cpu_total / successful_samples))
    avg_mem=$((mem_total / successful_samples))

    # Fix min values if no valid samples were collected
    [[ $min_cpu -eq 999999 ]] && min_cpu=0
    [[ $min_mem -eq 999999 ]] && min_mem=0

    echo "Statistics:"
    echo "  CPU Usage:"
    echo "    Average: ${avg_cpu}%"
    echo "    Min:     ${min_cpu}%"
    echo "    Max:     ${max_cpu}%"
    echo ""
    echo "  Memory Usage:"
    echo "    Average: ${avg_mem}%"
    echo "    Min:     ${min_mem}%"
    echo "    Max:     ${max_mem}%"
    echo ""
fi

# Get I/O stats if available
if command -v iostat >/dev/null 2>&1; then
    echo " I/O Statistics:"
    iostat -d 1 2 | tail -n +3
    echo ""
fi

# Child processes
CHILD_COUNT=$(pgrep -P "$PID" 2>/dev/null | wc -l)
if [[ $CHILD_COUNT -gt 0 ]]; then
    echo "👥 Child Processes: $CHILD_COUNT"
    echo ""
fi

# Recommendations
echo "========================================================"
echo "Recommendations:"

if [[ $max_cpu -gt 90 ]]; then
    echo "  High CPU usage detected. Consider:"
    echo "     - Using a higher weight for this job type"
    echo "     - Running fewer concurrent jobs"
fi

if [[ $max_mem -gt 80 ]]; then
    echo "  High memory usage detected. Consider:"
    echo "     - Monitoring for memory leaks"
    echo "     - Increasing system RAM if jobs fail"
fi

if [[ $max_cpu -lt 20 && $max_mem -lt 20 ]]; then
    echo "  Low resource usage - you could run more concurrent jobs"
fi

echo ""
echo "For continuous monitoring: $SCRIPT_NAME -watch $JOB_ID"
