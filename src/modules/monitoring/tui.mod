#!/bin/bash
# tui.mod - Interactive Terminal UI
# Full-screen interactive interface like htop

# Terminal control sequences
readonly CLEAR_SCREEN=$'\e[2J'
readonly MOVE_HOME=$'\e[H'
readonly HIDE_CURSOR=$'\e[?25l'
readonly SHOW_CURSOR=$'\e[?25h'
readonly BOLD=$'\e[1m'
readonly RESET=$'\e[0m'
readonly RED=$'\e[31m'
readonly GREEN=$'\e[32m'
readonly YELLOW=$'\e[33m'
readonly BLUE=$'\e[34m'
readonly CYAN=$'\e[36m'
readonly WHITE=$'\e[37m'

# TUI state
selected_index=0
scroll_offset=0
max_display_lines=15

# Cleanup on exit
cleanup() {
    echo -n "$SHOW_CURSOR"
    stty echo
    echo ""
    exit 0
}

trap cleanup EXIT INT TERM

# Hide cursor and disable echo (with error handling)
echo -n "$HIDE_CURSOR"
if ! stty -echo 2>/dev/null; then
    echo "ERROR: Cannot configure terminal (stty failed)"
    echo "TUI requires an interactive terminal"
    exit 1
fi

# Get terminal dimensions
get_terminal_height() {
    tput lines 2>/dev/null || echo "40"
}

# Collect job data
collect_jobs() {
    jobs_data=()
    local index=0

    for job_dir in "$JOB_DIR"/job_*; do
        [[ ! -d "$job_dir" ]] && continue
        [[ ! -f "$job_dir/job.info" ]] && continue

        local job_id=$(basename "$job_dir")
        local status=$(grep "^STATUS=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
        local job_name=$(grep "^JOB_NAME=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
        local priority=$(grep "^PRIORITY=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
        local weight=$(grep "^WEIGHT=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
        local start_time=$(grep "^START_TIME=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)

        # Calculate runtime for running jobs
        local runtime="N/A"
        if [[ "$status" == "RUNNING" && -n "$start_time" && "$start_time" != "N/A" ]]; then
            local start_epoch=$(date -d "$start_time" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$start_time" +%s 2>/dev/null)
            local now_epoch=$(date +%s)
            if [[ -n "$start_epoch" ]]; then
                local duration=$((now_epoch - start_epoch))
                runtime="$((duration / 60))m$((duration % 60))s"
            fi
        fi

        jobs_data+=("$index|$job_id|$status|$job_name|$priority|$weight|$runtime")
        index=$((index + 1))
    done
}

# Draw the interface
draw_interface() {
    echo -n "$CLEAR_SCREEN$MOVE_HOME"

    # Header
    echo "${BOLD}===============================================================================${RESET}"
    echo "${BOLD}                    📺 JOB SCHEDULER - INTERACTIVE TUI${RESET}"
    echo "${BOLD}===============================================================================${RESET}"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')                     Jobs: ${#jobs_data[@]}"
    echo "${BOLD}===============================================================================${RESET}"
    echo ""

    # Calculate resource usage
    local total_weight=0
    local running_count=0
    local queued_count=0

    for job_dir in "$JOB_DIR"/job_*; do
        [[ ! -d "$job_dir" ]] && continue
        [[ ! -f "$job_dir/job.info" ]] && continue

        local status=$(grep "^STATUS=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)

        if [[ "$status" == "RUNNING" ]]; then
            running_count=$((running_count + 1))
            if [[ -f "$job_dir/job.pid" ]]; then
                local pid=$(cat "$job_dir/job.pid" 2>/dev/null)
                if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
                    local weight=$(grep "^WEIGHT=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
                    [[ -n "$weight" && "$weight" =~ ^[0-9]+$ ]] && total_weight=$((total_weight + weight))
                fi
            fi
        elif [[ "$status" == "QUEUED" ]]; then
            queued_count=$((queued_count + 1))
        fi
    done

    # Resource bars
    local weight_percent=0
    local job_percent=0
    [[ "$MAX_TOTAL_WEIGHT" -gt 0 ]] && weight_percent=$((total_weight * 100 / MAX_TOTAL_WEIGHT))
    [[ "$MAX_CONCURRENT_JOBS" -gt 0 ]] && job_percent=$((running_count * 100 / MAX_CONCURRENT_JOBS))

    printf "Weight: %3d/%3d [" "$total_weight" "$MAX_TOTAL_WEIGHT"
    local bar_length=$((weight_percent / 4))
    for ((i=0; i<25; i++)); do
        if [[ $i -lt $bar_length ]]; then printf "#"; else printf "-"; fi
    done
    printf "] %3d%%   Jobs: %3d/%3d [" "$weight_percent" "$running_count" "$MAX_CONCURRENT_JOBS"
    bar_length=$((job_percent / 4))
    for ((i=0; i<25; i++)); do
        if [[ $i -lt $bar_length ]]; then printf "#"; else printf "-"; fi
    done
    printf "] %3d%%\n" "$job_percent"
    echo ""

    # Column headers
    printf "${BOLD}%-3s %-12s %-10s %-25s %-8s %-5s %-10s${RESET}\n" \
        " " "JOB_ID" "STATUS" "NAME" "PRIORITY" "WGHT" "RUNTIME"
    echo "───────────────────────────────────────────────────────────────────────────────"

    # Job list
    local terminal_height=$(get_terminal_height)
    max_display_lines=$((terminal_height - 18))

    # Ensure minimum display lines (terminal must be at least 23 lines)
    if [[ $max_display_lines -lt 1 ]]; then
        max_display_lines=1
        echo "Terminal too small (height: $terminal_height). Minimum 23 lines recommended."
    elif [[ $max_display_lines -lt 5 ]]; then
        max_display_lines=5
    fi

    local end_index=$((scroll_offset + max_display_lines))
    [[ $end_index -gt ${#jobs_data[@]} ]] && end_index=${#jobs_data[@]}

    for ((i=scroll_offset; i<end_index; i++)); do
        IFS='|' read -r index job_id status job_name priority weight runtime <<< "${jobs_data[$i]}"

        # Status color
        local status_color=""
        case "$status" in
            RUNNING) status_color="$GREEN" ;;
            QUEUED) status_color="$YELLOW" ;;
            PAUSED) status_color="$CYAN" ;;
            COMPLETED) status_color="$BLUE" ;;
            FAILED) status_color="$RED" ;;
            *) status_color="$WHITE" ;;
        esac

        # Priority icon
        local p_icon=""
        case "$priority" in
            urgent) p_icon="" ;;
            high) p_icon="" ;;
            low) p_icon="" ;;
            *) p_icon="" ;;
        esac

        # Highlight selected job
        local prefix="   "
        local highlight=""
        if [[ $i -eq $selected_index ]]; then
            prefix=">>>"
            highlight="${BOLD}${WHITE}"
        fi

        # Truncate name if too long
        [[ ${#job_name} -gt 25 ]] && job_name="${job_name:0:22}..."

        printf "${highlight}%-3s %-12s ${status_color}%-10s${RESET}${highlight} %-25s %-8s %-5s %-10s${RESET}\n" \
            "$prefix" "$job_id" "$status" "$job_name" "$priority" "$weight" "$runtime"
    done

    # Show scroll indicator
    if [[ ${#jobs_data[@]} -gt $max_display_lines ]]; then
        echo ""
        echo "Showing $((scroll_offset + 1))-$end_index of ${#jobs_data[@]} jobs"
    fi

    # Footer with key bindings
    echo ""
    echo "${BOLD}===============================================================================${RESET}"
    echo "${BOLD}Keys:${RESET} ↑/↓:Navigate  ${GREEN}Enter${RESET}:Info  ${YELLOW}P${RESET}:Pause  ${GREEN}R${RESET}:Resume  ${RED}K${RESET}:Kill  ${CYAN}L${RESET}:Logs  ${WHITE}Q${RESET}:Quit"
    echo "${BOLD}===============================================================================${RESET}"
}

# Get selected job ID
get_selected_job() {
    if [[ ${#jobs_data[@]} -eq 0 ]]; then
        echo ""
        return
    fi

    if [[ $selected_index -ge ${#jobs_data[@]} ]]; then
        selected_index=$((${#jobs_data[@]} - 1))
    fi

    if [[ $selected_index -lt 0 ]]; then
        selected_index=0
    fi

    IFS='|' read -r index job_id status job_name priority weight runtime <<< "${jobs_data[$selected_index]}"
    echo "$job_id"
}

# Handle key press
handle_key() {
    local key="$1"
    local selected_job=$(get_selected_job)

    case "$key" in
        A) # Up arrow
            if [[ $selected_index -gt 0 ]]; then
                selected_index=$((selected_index - 1))

                # Scroll up if needed
                if [[ $selected_index -lt $scroll_offset ]]; then
                    scroll_offset=$selected_index
                fi
            fi
            ;;

        B) # Down arrow
            if [[ $selected_index -lt $((${#jobs_data[@]} - 1)) ]]; then
                selected_index=$((selected_index + 1))

                # Scroll down if needed
                if [[ $selected_index -ge $((scroll_offset + max_display_lines)) ]]; then
                    scroll_offset=$((selected_index - max_display_lines + 1))
                fi
            fi
            ;;

        "") # Enter - show info
            if [[ -n "$selected_job" ]]; then
                echo -n "$SHOW_CURSOR"
                stty echo
                echo ""
                echo ""
                source "$MODULES_DIR/monitoring/info.mod" "$selected_job"
                echo ""
                echo "Press Enter to continue..."
                read -r
                echo -n "$HIDE_CURSOR"
                stty -echo
            fi
            ;;

        k|K) # Kill job
            if [[ -n "$selected_job" ]]; then
                echo -n "$SHOW_CURSOR"
                stty echo
                echo ""
                echo ""
                echo "${RED}${BOLD}Kill job $selected_job? (y/N):${RESET} "
                read -r confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    source "$MODULES_DIR/control/kill.mod" "$selected_job"
                    sleep 1
                fi
                echo -n "$HIDE_CURSOR"
                stty -echo
            fi
            ;;

        p|P) # Pause job
            if [[ -n "$selected_job" ]]; then
                echo -n "$SHOW_CURSOR"
                stty echo
                echo ""
                echo ""
                source "$MODULES_DIR/control/pause.mod" "$selected_job"
                sleep 1
                echo -n "$HIDE_CURSOR"
                stty -echo
            fi
            ;;

        r|R) # Resume job
            if [[ -n "$selected_job" ]]; then
                echo -n "$SHOW_CURSOR"
                stty echo
                echo ""
                echo ""
                source "$MODULES_DIR/control/resume.mod" "$selected_job"
                sleep 1
                echo -n "$HIDE_CURSOR"
                stty -echo
            fi
            ;;

        l|L) # Show logs
            if [[ -n "$selected_job" ]]; then
                echo -n "$SHOW_CURSOR"
                stty echo
                echo ""
                echo ""
                source "$MODULES_DIR/monitoring/logs.mod" "$selected_job" "tail"
                echo ""
                echo "Press Enter to continue..."
                read -r
                echo -n "$HIDE_CURSOR"
                stty -echo
            fi
            ;;

        q|Q) # Quit
            cleanup
            ;;
    esac
}

# Main loop
echo "Loading Interactive TUI..."
sleep 0.5

while true; do
    # Collect current job data
    collect_jobs

    # Draw interface
    draw_interface

    # Read key with timeout (1 second for auto-refresh)
    if read -rsn1 -t 1 key; then
        # Check for escape sequences (arrow keys)
        if [[ "$key" == $'\e' ]]; then
            read -rsn2 -t 0.1 key
            key="${key:1}"  # Remove the '['
        fi

        handle_key "$key"
    fi
done
