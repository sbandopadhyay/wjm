#!/bin/bash
# search.mod - Smart Search & History

# Parse search parameters
SEARCH_NAME=""
SEARCH_STATUS=""
SEARCH_PRIORITY=""
SEARCH_DATE=""
SEARCH_USER=""
INCLUDE_ARCHIVE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name) SEARCH_NAME="$2"; shift 2 ;;
        --status) SEARCH_STATUS="$2"; shift 2 ;;
        --priority) SEARCH_PRIORITY="$2"; shift 2 ;;
        --date) SEARCH_DATE="$2"; shift 2 ;;
        --user) SEARCH_USER="$2"; shift 2 ;;
        --include-archive) INCLUDE_ARCHIVE=1; shift ;;
        *)
            if [[ -z "$SEARCH_NAME" ]]; then
                SEARCH_NAME="$1"
            fi
            shift
            ;;
    esac
done

# Show help if no search criteria
if [[ -z "$SEARCH_NAME" && -z "$SEARCH_STATUS" && -z "$SEARCH_PRIORITY" && -z "$SEARCH_DATE" && -z "$SEARCH_USER" ]]; then
    echo "Smart Job Search"
    echo "========================================================"
    echo ""
    echo "Usage: $SCRIPT_NAME -search [options] [keyword]"
    echo ""
    echo "Search Options:"
    echo "  --name <text>       Search in job names"
    echo "  --status <status>   Filter by status (RUNNING/COMPLETED/FAILED/etc.)"
    echo "  --priority <level>  Filter by priority (urgent/high/normal/low)"
    echo "  --date <YYYY-MM-DD> Filter by submission date"
    echo "  --user <username>   Filter by user"
    echo "  --include-archive   Include archived jobs in search"
    echo ""
    echo "Examples:"
    echo "  $SCRIPT_NAME -search --name training"
    echo "  $SCRIPT_NAME -search --status COMPLETED --priority high"
    echo "  $SCRIPT_NAME -search --date 2025-10-24"
    echo "  $SCRIPT_NAME -search training --status RUNNING"
    echo "  $SCRIPT_NAME -search --include-archive --name model"
    exit 0
fi

echo "Search Results"
echo "========================================================"
echo ""

# Display search criteria
echo "Search Criteria:"
[[ -n "$SEARCH_NAME" ]] && echo "  Name contains: '$SEARCH_NAME'"
[[ -n "$SEARCH_STATUS" ]] && echo "  Status: $SEARCH_STATUS"
[[ -n "$SEARCH_PRIORITY" ]] && echo "  Priority: $SEARCH_PRIORITY"
[[ -n "$SEARCH_DATE" ]] && echo "  Date: $SEARCH_DATE"
[[ -n "$SEARCH_USER" ]] && echo "  User: $SEARCH_USER"
[[ $INCLUDE_ARCHIVE -eq 1 ]] && echo "  Including: Archived jobs"
echo ""

# Search active jobs
results_count=0
MAX_RESULTS=100  # Prevent overwhelming output

search_directory() {
    local search_dir="$1"
    local is_archive="$2"

    for job_dir in "$search_dir"/job_*; do
        [[ ! -d "$job_dir" ]] && continue
        [[ ! -f "$job_dir/job.info" ]] && continue

        # Stop if we've reached the result limit
        [[ $results_count -ge $MAX_RESULTS ]] && return

        # Read job metadata
        local job_id=$(basename "$job_dir")
        local status=$(grep "^STATUS=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
        local job_name=$(grep "^JOB_NAME=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
        local priority=$(grep "^PRIORITY=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
        local submit_time=$(grep "^SUBMIT_TIME=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)
        local user=$(grep "^USER=" "$job_dir/job.info" 2>/dev/null | cut -d= -f2)

        # Apply filters
        local match=1

        # Name filter (use glob matching, not regex - safer and more intuitive)
        if [[ -n "$SEARCH_NAME" ]]; then
            # Convert to lowercase for case-insensitive matching
            local job_name_lower=$(echo "$job_name" | tr '[:upper:]' '[:lower:]')
            local job_id_lower=$(echo "$job_id" | tr '[:upper:]' '[:lower:]')
            local search_lower=$(echo "$SEARCH_NAME" | tr '[:upper:]' '[:lower:]')

            if [[ ! "$job_name_lower" == *"$search_lower"* && ! "$job_id_lower" == *"$search_lower"* ]]; then
                match=0
            fi
        fi

        # Status filter
        if [[ -n "$SEARCH_STATUS" && "$status" != "$SEARCH_STATUS" ]]; then
            match=0
        fi

        # Priority filter
        if [[ -n "$SEARCH_PRIORITY" && "$priority" != "$SEARCH_PRIORITY" ]]; then
            match=0
        fi

        # Date filter (use prefix match instead of regex)
        if [[ -n "$SEARCH_DATE" ]]; then
            if [[ ! "$submit_time" == "$SEARCH_DATE"* ]]; then
                match=0
            fi
        fi

        # User filter
        if [[ -n "$SEARCH_USER" && "$user" != "$SEARCH_USER" ]]; then
            match=0
        fi

        # If match, display result
        if [[ $match -eq 1 ]]; then
            results_count=$((results_count + 1))

            # Status indicator
            case "$status" in
                RUNNING) status_icon="[RUN]" ;;
                COMPLETED) status_icon="[OK] " ;;
                FAILED) status_icon="[ERR]" ;;
                QUEUED) status_icon="[QUE]" ;;
                PAUSED) status_icon="[PAU]" ;;
                KILLED) status_icon="[KIL]" ;;
                *) status_icon="[   ]" ;;
            esac

            # Priority indicator
            case "$priority" in
                urgent) priority_icon="[!]" ;;
                high) priority_icon="[H]" ;;
                low) priority_icon="[L]" ;;
                *) priority_icon="[N]" ;;
            esac

            # Display result
            echo "$status_icon $priority_icon $job_id"
            [[ -n "$job_name" && "$job_name" != "N/A" ]] && echo "      Name: $job_name"
            echo "      Status: $status  |  Priority: $priority"
            echo "      Submitted: $submit_time  |  User: $user"
            [[ $is_archive -eq 1 ]] && echo "      Location: Archived"
            echo ""
        fi
    done
}

# Search active jobs
search_directory "$JOB_DIR" 0

# Search archived jobs if requested
if [[ $INCLUDE_ARCHIVE -eq 1 && -d "$ARCHIVE_DIR" ]]; then
    for archive_batch in "$ARCHIVE_DIR"/[0-9][0-9][0-9]; do
        [[ -d "$archive_batch" ]] && search_directory "$archive_batch" 1
    done
fi

# Summary
echo "========================================================"
if [[ $results_count -eq 0 ]]; then
    echo "No jobs found matching search criteria."
else
    echo "Found $results_count matching job(s)"
    if [[ $results_count -ge $MAX_RESULTS ]]; then
        echo ""
        echo "Result limit reached ($MAX_RESULTS). Refine your search for more results."
    fi
fi
