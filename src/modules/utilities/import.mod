#!/bin/bash
# import.mod - Import job configurations
# v1.1 Feature: Import job settings and apply to new submissions

# Parse arguments
CONFIG_FILE=""
JOB_FILE=""
DRY_RUN=0
SUBMIT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config|-c)
            if [[ -z "$2" ]]; then
                error_msg "--config flag requires a file path"
                exit 1
            fi
            CONFIG_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --submit)
            SUBMIT=1
            shift
            ;;
        *)
            if [[ -z "$JOB_FILE" ]]; then
                JOB_FILE="$1"
            fi
            shift
            ;;
    esac
done

# Validate input
if [[ -z "$CONFIG_FILE" ]]; then
    error_msg "Please specify a config file to import"
    echo "Usage: $SCRIPT_NAME -import --config <file> [job.run] [--dry-run] [--submit]"
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    error_msg "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Detect format and parse
parse_yaml() {
    local file="$1"

    # Simple YAML parser for our format
    while IFS=: read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Clean up key and value
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')

        case "$key" in
            weight) IMPORT_WEIGHT="$value" ;;
            gpu) IMPORT_GPU="$value" ;;
            cpu) IMPORT_CPU="$value" ;;
            memory) IMPORT_MEMORY="$value" ;;
            priority) IMPORT_PRIORITY="$value" ;;
            timeout) IMPORT_TIMEOUT="$value" ;;
            max) IMPORT_RETRY="$value" ;;
            delay) IMPORT_RETRY_DELAY="$value" ;;
            project) IMPORT_PROJECT="$value" ;;
            group) IMPORT_GROUP="$value" ;;
            pre) IMPORT_PRE_HOOK="$value" ;;
            post) IMPORT_POST_HOOK="$value" ;;
            on_fail) IMPORT_ON_FAIL="$value" ;;
            on_success) IMPORT_ON_SUCCESS="$value" ;;
        esac
    done < "$file"
}

parse_json() {
    local file="$1"

    # Simple JSON parser using grep/sed (no jq dependency)
    IMPORT_WEIGHT=$(grep -o '"weight"[[:space:]]*:[[:space:]]*[0-9]*' "$file" | head -1 | grep -o '[0-9]*$')
    IMPORT_GPU=$(grep -o '"gpu"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    IMPORT_CPU=$(grep -o '"cpu"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    IMPORT_MEMORY=$(grep -o '"memory"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    IMPORT_PRIORITY=$(grep -o '"priority"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    IMPORT_TIMEOUT=$(grep -o '"timeout"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    IMPORT_RETRY=$(grep -o '"max"[[:space:]]*:[[:space:]]*[0-9]*' "$file" | head -1 | grep -o '[0-9]*$')
    IMPORT_PROJECT=$(grep -o '"project"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    IMPORT_GROUP=$(grep -o '"group"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
}

parse_shell() {
    local file="$1"

    # Parse shell format - extract WJM_ exports
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^export[[:space:]]+ ]] && key="${key#export }"
        value=$(echo "$value" | sed 's/^"//;s/"$//')

        case "$key" in
            WJM_WEIGHT) IMPORT_WEIGHT="$value" ;;
            WJM_GPU) IMPORT_GPU="$value" ;;
            WJM_CPU) IMPORT_CPU="$value" ;;
            WJM_MEMORY) IMPORT_MEMORY="$value" ;;
            WJM_PRIORITY) IMPORT_PRIORITY="$value" ;;
            WJM_TIMEOUT) IMPORT_TIMEOUT="$value" ;;
            WJM_RETRY) IMPORT_RETRY="$value" ;;
            WJM_PROJECT) IMPORT_PROJECT="$value" ;;
        esac
    done < "$file"
}

# Initialize import variables
IMPORT_WEIGHT=""
IMPORT_GPU=""
IMPORT_CPU=""
IMPORT_MEMORY=""
IMPORT_PRIORITY=""
IMPORT_TIMEOUT=""
IMPORT_RETRY=""
IMPORT_RETRY_DELAY=""
IMPORT_PROJECT=""
IMPORT_GROUP=""
IMPORT_PRE_HOOK=""
IMPORT_POST_HOOK=""
IMPORT_ON_FAIL=""
IMPORT_ON_SUCCESS=""

# Detect format and parse
if grep -q '^\s*{' "$CONFIG_FILE" 2>/dev/null; then
    parse_json "$CONFIG_FILE"
elif grep -q '^export WJM_' "$CONFIG_FILE" 2>/dev/null; then
    parse_shell "$CONFIG_FILE"
else
    parse_yaml "$CONFIG_FILE"
fi

# Display imported configuration
echo "Imported Configuration"
echo "======================"
echo ""
echo "Resources:"
[[ -n "$IMPORT_WEIGHT" && "$IMPORT_WEIGHT" != "N/A" ]] && echo "  Weight:   $IMPORT_WEIGHT"
[[ -n "$IMPORT_GPU" && "$IMPORT_GPU" != "N/A" ]] && echo "  GPU:      $IMPORT_GPU"
[[ -n "$IMPORT_CPU" && "$IMPORT_CPU" != "N/A" ]] && echo "  CPU:      $IMPORT_CPU"
[[ -n "$IMPORT_MEMORY" && "$IMPORT_MEMORY" != "N/A" ]] && echo "  Memory:   $IMPORT_MEMORY"
echo ""
echo "Scheduling:"
[[ -n "$IMPORT_PRIORITY" && "$IMPORT_PRIORITY" != "N/A" ]] && echo "  Priority: $IMPORT_PRIORITY"
[[ -n "$IMPORT_TIMEOUT" && "$IMPORT_TIMEOUT" != "N/A" ]] && echo "  Timeout:  $IMPORT_TIMEOUT"
echo ""
echo "Retry:"
[[ -n "$IMPORT_RETRY" && "$IMPORT_RETRY" != "0" ]] && echo "  Max:      $IMPORT_RETRY"
[[ -n "$IMPORT_RETRY_DELAY" ]] && echo "  Delay:    ${IMPORT_RETRY_DELAY}s"
echo ""
echo "Organization:"
[[ -n "$IMPORT_PROJECT" && "$IMPORT_PROJECT" != "N/A" ]] && echo "  Project:  $IMPORT_PROJECT"
[[ -n "$IMPORT_GROUP" && "$IMPORT_GROUP" != "N/A" ]] && echo "  Group:    $IMPORT_GROUP"
echo ""

# If dry run, just show what would happen
if [[ $DRY_RUN -eq 1 ]]; then
    echo "Dry run mode - no changes made"
    if [[ -n "$JOB_FILE" ]]; then
        echo ""
        echo "Command that would be executed:"
        CMD="$SCRIPT_NAME -qrun $JOB_FILE"
        [[ -n "$IMPORT_PRIORITY" && "$IMPORT_PRIORITY" != "N/A" ]] && CMD="$CMD --priority $IMPORT_PRIORITY"
        [[ -n "$IMPORT_TIMEOUT" && "$IMPORT_TIMEOUT" != "N/A" ]] && CMD="$CMD --timeout $IMPORT_TIMEOUT"
        [[ -n "$IMPORT_RETRY" && "$IMPORT_RETRY" != "0" ]] && CMD="$CMD --retry $IMPORT_RETRY"
        [[ -n "$IMPORT_PROJECT" && "$IMPORT_PROJECT" != "N/A" ]] && CMD="$CMD --project $IMPORT_PROJECT"
        [[ -n "$IMPORT_CPU" && "$IMPORT_CPU" != "N/A" ]] && CMD="$CMD --cpu $IMPORT_CPU"
        [[ -n "$IMPORT_MEMORY" && "$IMPORT_MEMORY" != "N/A" ]] && CMD="$CMD --memory $IMPORT_MEMORY"
        echo "  $CMD"
    fi
    exit 0
fi

# If job file provided and --submit, submit the job
if [[ -n "$JOB_FILE" && $SUBMIT -eq 1 ]]; then
    if [[ ! -f "$JOB_FILE" ]]; then
        error_msg "Job file not found: $JOB_FILE"
        exit 1
    fi

    # Build command
    CMD_ARGS=("$JOB_FILE")
    [[ -n "$IMPORT_PRIORITY" && "$IMPORT_PRIORITY" != "N/A" ]] && CMD_ARGS+=("--priority" "$IMPORT_PRIORITY")
    [[ -n "$IMPORT_TIMEOUT" && "$IMPORT_TIMEOUT" != "N/A" ]] && CMD_ARGS+=("--timeout" "$IMPORT_TIMEOUT")
    [[ -n "$IMPORT_RETRY" && "$IMPORT_RETRY" != "0" ]] && CMD_ARGS+=("--retry" "$IMPORT_RETRY")
    [[ -n "$IMPORT_PROJECT" && "$IMPORT_PROJECT" != "N/A" ]] && CMD_ARGS+=("--project" "$IMPORT_PROJECT")
    [[ -n "$IMPORT_CPU" && "$IMPORT_CPU" != "N/A" ]] && CMD_ARGS+=("--cpu" "$IMPORT_CPU")
    [[ -n "$IMPORT_MEMORY" && "$IMPORT_MEMORY" != "N/A" ]] && CMD_ARGS+=("--memory" "$IMPORT_MEMORY")

    echo "Submitting job with imported configuration..."
    source "$MODULES_DIR/core/qrun.mod" "${CMD_ARGS[@]}"
elif [[ -n "$JOB_FILE" ]]; then
    echo "Job file specified but --submit not provided."
    echo "Use --submit to submit the job with these settings, or --dry-run to preview."
fi
