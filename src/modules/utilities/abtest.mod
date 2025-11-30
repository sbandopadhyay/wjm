#!/bin/bash
# abtest.mod - A/B Testing Framework

SCRIPT_FILE="$1"
shift

if [[ -z "$SCRIPT_FILE" ]]; then
    echo "🧪 A/B Testing Framework"
    echo "========================================================"
    echo ""
    echo "Run the same job with different parameters and compare results."
    echo ""
    echo "Usage: $SCRIPT_NAME -abtest <script> --variants <n> [--params \"PARAMS\"]"
    echo ""
    echo "Options:"
    echo "  --variants <n>       Number of variants to run (default: 2)"
    echo "  --params \"VAR=val\"   Parameters to vary (space-separated)"
    echo "  --preset <preset>    Use preset for all variants"
    echo "  --priority <level>   Priority for all test jobs"
    echo ""
    echo "Examples:"
    echo "  # Simple A/B test with 2 variants"
    echo "  $SCRIPT_NAME -abtest train.sh --variants 2 --params \"LR=0.001 LR=0.01\""
    echo ""
    echo "  # Test 3 different learning rates"
    echo "  $SCRIPT_NAME -abtest train.sh --variants 3 --params \"LR=0.001 LR=0.01 LR=0.1\""
    exit 0
fi

# Parse options
VARIANTS=2
PARAMS_LIST=()
PRESET=""
PRIORITY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variants) VARIANTS="$2"; shift 2 ;;
        --params)
            shift
            # Read all params until next flag or end
            while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                PARAMS_LIST+=("$1")
                shift
            done
            ;;
        --preset) PRESET="$2"; shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Validate script
if [[ ! -f "$SCRIPT_FILE" ]]; then
    error_msg "Script file '$SCRIPT_FILE' not found"
    exit 1
fi

# Validate variants
if [[ ! "$VARIANTS" =~ ^[0-9]+$ || "$VARIANTS" -lt 2 ]]; then
    error_msg "Variants must be a number >= 2"
    exit 1
fi

if [[ "$VARIANTS" -gt 26 ]]; then
    error_msg "Maximum 26 variants supported (A-Z)"
    exit 1
fi

# Validate parameters format (VAR=value)
for param in "${PARAMS_LIST[@]}"; do
    if [[ ! "$param" =~ ^[A-Za-z_][A-Za-z0-9_]*=.+$ ]]; then
        error_msg "Invalid parameter format: '$param'. Expected: VAR=value"
        exit 1
    fi
done

# If no params provided, just run N copies
if [[ ${#PARAMS_LIST[@]} -eq 0 ]]; then
    warn_msg "No parameters specified - will run $VARIANTS identical jobs"
fi

echo "🧪 A/B Test Setup"
echo "========================================================"
echo "  Script:   $SCRIPT_FILE"
echo "  Variants: $VARIANTS"
[[ -n "$PRESET" ]] && echo "  Preset:   $PRESET"
[[ -n "$PRIORITY" ]] && echo "  Priority: $PRIORITY"
[[ ${#PARAMS_LIST[@]} -gt 0 ]] && echo "  Params:   ${PARAMS_LIST[*]}"
echo ""

# Create A/B test directory
ABTEST_ID="abtest_$(date +%Y%m%d_%H%M%S)"
ABTEST_DIR="$JOB_DIR/.abtests/$ABTEST_ID"
mkdir -p "$ABTEST_DIR"

# Store metadata
cat > "$ABTEST_DIR/metadata.conf" <<EOF
SCRIPT=$SCRIPT_FILE
VARIANTS=$VARIANTS
CREATED=$(date '+%Y-%m-%d %H:%M:%S')
PARAMS=${PARAMS_LIST[*]}
PRESET=$PRESET
PRIORITY=$PRIORITY
EOF

echo " Submitting $VARIANTS test jobs..."
echo ""

# Submit variants
declare -a JOB_IDS=()
declare -a TEMP_SCRIPTS=()

# Check /tmp space BEFORE creating files
check_tmp_space() {
    local required_mb=100  # 100MB minimum
    local available_kb=$(df /tmp | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))

    if [[ $available_mb -lt $required_mb ]]; then
        error_msg "Insufficient /tmp space: ${available_mb}MB available, need ${required_mb}MB"
        return 1
    fi
    return 0
}

# Check space first
check_tmp_space || exit 1

# Cleanup function for temp files (more aggressive)
cleanup_temps() {
    for temp_file in "${TEMP_SCRIPTS[@]}"; do
        rm -f "$temp_file" 2>/dev/null
    done
    TEMP_SCRIPTS=()  # Clear array
}
trap cleanup_temps EXIT INT TERM HUP

for ((i=0; i<VARIANTS; i++)); do
    variant_letter=$(printf "%c" $((65 + i)))  # A, B, C, ...
    variant_name="Variant $variant_letter"

    # Create modified script with parameters
    TEMP_SCRIPT=$(mktemp "/tmp/abtest_${variant_letter}_XXXXXX.sh") || {
        error_msg "Failed to create temp file"
        cleanup_temps
        exit 1
    }
    TEMP_SCRIPTS+=("$TEMP_SCRIPT")

    # Add parameter exports to script
    if [[ ${#PARAMS_LIST[@]} -gt $i ]]; then
        param="${PARAMS_LIST[$i]}"
        echo "# A/B Test Variant $variant_letter: $param" > "$TEMP_SCRIPT"
        echo "export $param" >> "$TEMP_SCRIPT"
    else
        echo "# A/B Test Variant $variant_letter" > "$TEMP_SCRIPT"
    fi

    cat "$SCRIPT_FILE" >> "$TEMP_SCRIPT"
    chmod +x "$TEMP_SCRIPT"

    # Build submission command
    CMD_ARGS=("$TEMP_SCRIPT" "--name" "$ABTEST_ID - $variant_name")

    [[ -n "$PRESET" ]] && CMD_ARGS+=("--preset" "$PRESET")
    [[ -n "$PRIORITY" ]] && CMD_ARGS+=("--priority" "$PRIORITY")

    # Submit job
    echo "  🧪 Submitting Variant $variant_letter..."
    OUTPUT=$(source "$MODULES_DIR/core/qrun.mod" "${CMD_ARGS[@]}" 2>&1)

    # Extract job ID from output
    JOB_ID=$(echo "$OUTPUT" | grep -o 'job_[0-9]\{3\}' | head -1)

    if [[ -n "$JOB_ID" ]]; then
        JOB_IDS+=("$JOB_ID")
        echo "     Job ID: $JOB_ID"

        # Store job ID in A/B test metadata
        echo "$JOB_ID" >> "$ABTEST_DIR/job_ids.txt"

        # Delete temp file immediately after submission
        rm -f "$TEMP_SCRIPT"
    else
        warn_msg "Failed to extract job ID for variant $variant_letter"
    fi
done

# Final cleanup
cleanup_temps

echo ""
echo "========================================================"
echo "A/B Test '$ABTEST_ID' started with ${#JOB_IDS[@]} variants"
echo ""
echo "Job IDs: ${JOB_IDS[*]}"
echo ""
echo "Monitor progress:"
echo "  $SCRIPT_NAME -watch all"
echo "  $SCRIPT_NAME -stats"
echo ""
echo "Compare results when complete:"
for ((i=0; i<${#JOB_IDS[@]}-1; i++)); do
    echo "  $SCRIPT_NAME -compare ${JOB_IDS[$i]} ${JOB_IDS[$((i+1))]}"
done
echo ""
echo "View all test jobs:"
echo "  $SCRIPT_NAME -search --name \"$ABTEST_ID\""
